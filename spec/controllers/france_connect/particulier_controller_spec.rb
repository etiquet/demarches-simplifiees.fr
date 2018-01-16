describe FranceConnect::ParticulierController, type: :controller do
  let(:code) { 'plop' }
  let(:given_name) { 'titi' }
  let(:family_name) { 'toto' }
  let(:birthdate) { '20150821' }
  let(:gender) { 'M' }
  let(:birthplace) { '1234' }
  let(:france_connect_particulier_id) { 'blabla' }
  let(:email) { 'test@test.com' }

  let(:user_info) { { france_connect_particulier_id: france_connect_particulier_id, given_name: given_name, family_name: family_name, birthdate: birthdate, birthplace: birthplace, gender: gender, email_france_connect: email } }

  describe '#auth' do
    subject { get :login }

    it { is_expected.to have_http_status(:redirect) }
  end

  describe '#callback' do
    subject { get :callback, params: {code: code} }

    context 'when param code is missing' do
      let(:code) { nil }

      it { is_expected.to redirect_to(new_user_session_path) }
    end

    context 'when param code is empty' do
      let(:code) { '' }

      it { is_expected.to redirect_to(new_user_session_path) }
    end

    context 'when code is correct' do
      before do
        allow(FranceConnectService).to receive(:retrieve_user_informations_particulier)
          .and_return(FranceConnectInformation.new(user_info))
      end

      context 'when france_connect_particulier_id exist in database' do
        let!(:france_connect_information) { create(:france_connect_information, france_connect_particulier_id: france_connect_particulier_id, given_name: given_name, family_name: family_name, birthdate: birthdate, gender: gender, birthplace: birthplace) }

        it { expect { subject }.not_to change { FranceConnectInformation.count } }

        context 'when france_connect_particulier_id have an associate user' do
          let!(:user) { create(:user, email: 'plop@plop.com', france_connect_information: france_connect_information) }

          it do
            subject
            expect(user.reload.loged_in_with_france_connect?).to be_truthy
          end

          context 'and the user has a stored location' do
            let(:stored_location) { '/plip/plop' }
            before { controller.store_location_for(:user, stored_location) }

            it { is_expected.to redirect_to(stored_location) }
          end
        end

        context 'when france_connect_particulier_id does not have an associate user' do
          before do
            get :callback, params: {code: code}
          end

          it {expect(response).to redirect_to(root_path)}
        end
      end

      context 'when france_connect_particulier_id does not exist in database' do
        let(:last_france_connect_information) { FranceConnectInformation.last }

        it { expect { subject }.to change { FranceConnectInformation.count }.by(1) }

        describe 'FranceConnectInformation attributs' do
          before do
            get :callback, params: {code: code}
          end

          subject { last_france_connect_information }

          it { expect(subject.gender).to eq gender }
          it { expect(subject.given_name).to eq given_name }
          it { expect(subject.family_name).to eq family_name }
          it { expect(subject.email_france_connect).to eq email }
          it { expect(subject.birthdate.to_time.to_i).to eq birthdate.to_time.to_i }
          it { expect(subject.birthplace).to eq birthplace }
          it { expect(subject.france_connect_particulier_id).to eq france_connect_particulier_id }
        end

        it { expect(subject).to redirect_to(root_path) }
      end
    end

    context 'when code is not correct' do
      before do
        allow(FranceConnectService).to receive(:retrieve_user_informations_particulier) { raise Rack::OAuth2::Client::Error.new(500, error: 'Unknown') }
        get :callback, params: {code: code}
      end

      it 'redirect to login page' do
        expect(response).to redirect_to(new_user_session_path)
      end

      it 'display error message' do
        expect(flash[:alert]).to be_present
      end
    end
  end
end
