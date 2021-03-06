FactoryBot.define do
  sequence(:groupe_label) { |n| "label_#{n}" }

  factory :groupe_instructeur do
    label { generate(:groupe_label) }
    procedure { create(:procedure) }
  end
end
