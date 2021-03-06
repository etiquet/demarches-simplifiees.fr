require Rails.root.join('lib', 'percentile')

class Procedure < ApplicationRecord
  self.ignored_columns = ['archived_at', 'csv_export_queued', 'xlsx_export_queued', 'ods_export_queued']

  include ProcedureStatsConcern

  include Discard::Model
  self.discard_column = :hidden_at
  default_scope -> { kept }

  MAX_DUREE_CONSERVATION = 36
  MAX_DUREE_CONSERVATION_EXPORT = 3.hours

  has_many :types_de_champ, -> { root.public_only.ordered }, inverse_of: :procedure, dependent: :destroy
  has_many :types_de_champ_private, -> { root.private_only.ordered }, class_name: 'TypeDeChamp', inverse_of: :procedure, dependent: :destroy
  has_many :deleted_dossiers, dependent: :destroy

  has_one :module_api_carto, dependent: :destroy
  has_one :attestation_template, dependent: :destroy

  belongs_to :parent_procedure, class_name: 'Procedure'
  belongs_to :canonical_procedure, class_name: 'Procedure'
  belongs_to :service

  has_many :administrateurs_procedures
  has_many :administrateurs, through: :administrateurs_procedures, after_remove: -> (procedure, _admin) { procedure.validate! }
  has_many :groupe_instructeurs, dependent: :destroy
  has_many :instructeurs, through: :groupe_instructeurs

  has_many :dossiers, through: :groupe_instructeurs, dependent: :restrict_with_exception

  has_one :initiated_mail, class_name: "Mails::InitiatedMail", dependent: :destroy
  has_one :received_mail, class_name: "Mails::ReceivedMail", dependent: :destroy
  has_one :closed_mail, class_name: "Mails::ClosedMail", dependent: :destroy
  has_one :refused_mail, class_name: "Mails::RefusedMail", dependent: :destroy
  has_one :without_continuation_mail, class_name: "Mails::WithoutContinuationMail", dependent: :destroy

  has_one :defaut_groupe_instructeur, -> { order(:id) }, class_name: 'GroupeInstructeur', inverse_of: :procedure

  has_one_attached :logo
  has_one_attached :notice
  has_one_attached :deliberation

  accepts_nested_attributes_for :types_de_champ, reject_if: proc { |attributes| attributes['libelle'].blank? }, allow_destroy: true
  accepts_nested_attributes_for :types_de_champ_private, reject_if: proc { |attributes| attributes['libelle'].blank? }, allow_destroy: true

  scope :brouillons,            -> { where(aasm_state: :brouillon) }
  scope :publiees,              -> { where(aasm_state: :publiee) }
  scope :closes,                -> { where(aasm_state: [:close, :depubliee]) }
  scope :publiees_ou_closes,    -> { where(aasm_state: [:publiee, :close, :depubliee]) }
  scope :by_libelle,            -> { order(libelle: :asc) }
  scope :created_during,        -> (range) { where(created_at: range) }
  scope :cloned_from_library,   -> { where(cloned_from_library: true) }
  scope :declarative,           -> { where.not(declarative_with_state: nil) }

  scope :discarded_expired, -> do
    with_discarded
      .discarded
      .where('hidden_at < ?', 1.month.ago)
  end

  scope :for_api, -> {
    includes(
      :administrateurs,
      :types_de_champ_private,
      :types_de_champ,
      :module_api_carto
    )
  }

  enum declarative_with_state: {
    en_instruction:  'en_instruction',
    accepte:         'accepte'
  }

  scope :for_api_v2, -> {
    includes(administrateurs: :user)
  }

  validates :libelle, presence: true, allow_blank: false, allow_nil: false
  validates :description, presence: true, allow_blank: false, allow_nil: false
  validates :administrateurs, presence: true
  validates :lien_site_web, presence: true, if: :publiee?
  validate :validate_for_publication, on: :publication
  validate :check_juridique
  validates :path, presence: true, format: { with: /\A[a-z0-9_\-]{3,50}\z/ }, uniqueness: { scope: [:path, :closed_at, :hidden_at, :unpublished_at], case_sensitive: false }
  validates :duree_conservation_dossiers_dans_ds, allow_nil: false, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_DUREE_CONSERVATION }
  validates :duree_conservation_dossiers_hors_ds, allow_nil: false, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates_with MonAvisEmbedValidator
  validates :notice, content_type: [
    "application/msword",
    "application/pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-powerpoint",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "application/vnd.oasis.opendocument.text",
    "application/vnd.oasis.opendocument.presentation",
    "text/plain"
  ], size: { less_than: 20.megabytes }

  validates :deliberation, content_type: [
    "application/msword",
    "application/pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "text/plain",
    "application/vnd.oasis.opendocument.text"
  ], size: { less_than: 20.megabytes }

  validates :logo, content_type: ['image/png', 'image/jpg', 'image/jpeg'], size: { less_than: 5.megabytes }
  before_save :update_juridique_required
  after_initialize :ensure_path_exists
  before_save :ensure_path_exists
  after_create :ensure_default_groupe_instructeur

  include AASM

  aasm whiny_persistence: true do
    state :brouillon, initial: true
    state :publiee
    state :close
    state :depubliee

    event :publish, before: :before_publish, after: :after_publish do
      transitions from: :brouillon, to: :publiee
      transitions from: :close, to: :publiee
      transitions from: :depubliee, to: :publiee
    end

    event :close, after: :after_close do
      transitions from: :publiee, to: :close
    end

    event :unpublish, after: :after_unpublish do
      transitions from: :publiee, to: :depubliee
    end
  end

  def publish_or_reopen!(administrateur)
    Procedure.transaction do
      if brouillon?
        reset!
      end

      other_procedure = other_procedure_with_path(path)
      if other_procedure.present? && administrateur.owns?(other_procedure)
        other_procedure.unpublish!
        publish!(other_procedure.canonical_procedure || other_procedure)
      else
        publish!
      end
    end
  end

  def reset!
    if locked?
      raise "Can not reset a locked procedure."
    else
      groupe_instructeurs.each { |gi| gi.dossiers.destroy_all }
    end
  end

  def validate_for_publication
    old_attributes = self.slice(:aasm_state, :closed_at)
    self.aasm_state = :publiee
    self.closed_at = nil

    is_valid = validate

    self.attributes = old_attributes

    is_valid
  end

  def suggested_path(administrateur)
    if path_customized?
      return path
    end
    slug = libelle&.parameterize&.first(50)
    suggestion = slug
    counter = 1
    while !path_available?(administrateur, suggestion)
      counter = counter + 1
      suggestion = "#{slug}-#{counter}"
    end
    suggestion
  end

  def other_procedure_with_path(path)
    Procedure.publiees
      .where.not(id: self.id)
      .find_by(path: path)
  end

  def path_available?(administrateur, path)
    procedure = other_procedure_with_path(path)

    procedure.blank? || administrateur.owns?(procedure)
  end

  def locked?
    publiee? || close? || depubliee?
  end

  def accepts_new_dossiers?
    publiee? || brouillon?
  end

  def dossier_can_transition_to_en_construction?
    accepts_new_dossiers? || depubliee?
  end

  def expose_legacy_carto_api?
    module_api_carto&.use_api_carto? && module_api_carto&.migrated?
  end

  def declarative?
    declarative_with_state.present?
  end

  def declarative_accepte?
    declarative_with_state == Procedure.declarative_with_states.fetch(:accepte)
  end

  def self.declarative_attributes_for_select
    declarative_with_states.map do |state, _|
      [I18n.t("activerecord.attributes.#{model_name.i18n_key}.declarative_with_state/#{state}"), state]
    end
  end

  # Warning: dossier after_save build_default_champs must be removed
  # to save a dossier created from this method
  def new_dossier
    Dossier.new(
      procedure: self,
      champs: build_champs,
      champs_private: build_champs_private,
      groupe_instructeur: defaut_groupe_instructeur
    )
  end

  def build_champs
    types_de_champ.map(&:build_champ)
  end

  def build_champs_private
    types_de_champ_private.map(&:build_champ)
  end

  def path_customized?
    !path.match?(/[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}/)
  end

  def organisation_name
    service&.nom || organisation
  end

  def self.active(id)
    publiees.find(id)
  end

  def switch_types_de_champ(index_of_first_element)
    switch_list_order(types_de_champ, index_of_first_element)
  end

  def switch_types_de_champ_private(index_of_first_element)
    switch_list_order(types_de_champ_private, index_of_first_element)
  end

  def switch_list_order(list, index_of_first_element)
    if index_of_first_element < 0 ||
      index_of_first_element == list.count - 1 ||
      list.count < 1

      false
    else
      list[index_of_first_element].update(order_place: index_of_first_element + 1)
      list[index_of_first_element + 1].update(order_place: index_of_first_element)
      reload

      true
    end
  end

  def clone(admin, from_library)
    is_different_admin = !admin.owns?(self)

    populate_champ_stable_ids
    include_list = {
      attestation_template: nil,
      types_de_champ: [:drop_down_list, types_de_champ: :drop_down_list],
      types_de_champ_private: [:drop_down_list, types_de_champ: :drop_down_list]
    }
    include_list[:groupe_instructeurs] = :instructeurs if !is_different_admin
    procedure = self.deep_clone(include: include_list, &method(:clone_attachments))
    procedure.path = SecureRandom.uuid
    procedure.aasm_state = :brouillon
    procedure.closed_at = nil
    procedure.unpublished_at = nil
    procedure.published_at = nil
    procedure.lien_notice = nil

    if is_different_admin || from_library
      procedure.types_de_champ.each { |tdc| tdc.options&.delete(:old_pj) }
    end

    if is_different_admin
      procedure.administrateurs = [admin]
    else
      procedure.administrateurs = administrateurs
    end

    procedure.initiated_mail = initiated_mail&.dup
    procedure.received_mail = received_mail&.dup
    procedure.closed_mail = closed_mail&.dup
    procedure.refused_mail = refused_mail&.dup
    procedure.without_continuation_mail = without_continuation_mail&.dup
    procedure.ask_birthday = false # see issue #4242

    procedure.cloned_from_library = from_library
    procedure.parent_procedure = self
    procedure.canonical_procedure = nil

    if from_library
      procedure.service = nil
    elsif self.service.present? && is_different_admin
      procedure.service = self.service.clone_and_assign_to_administrateur(admin)
    end

    procedure.save

    procedure
  end

  def clone_attachments(original, kopy)
    if original.is_a?(TypeDeChamp)
      clone_attachment(:piece_justificative_template, original, kopy)
    elsif original.is_a?(Procedure)
      clone_attachment(:logo, original, kopy)
      clone_attachment(:notice, original, kopy)
      clone_attachment(:deliberation, original, kopy)
    end
  end

  def clone_attachment(attribute, original, kopy)
    original_attachment = original.send(attribute)
    if original_attachment.attached?
      kopy.send(attribute).attach({
        io: StringIO.new(original_attachment.download),
        filename: original_attachment.filename,
        content_type: original_attachment.content_type,
        # we don't want to run virus scanner on cloned file
        metadata: { virus_scan_result: ActiveStorage::VirusScanner::SAFE }
      })
    end
  end

  def whitelisted?
    whitelisted_at.present?
  end

  def total_dossier
    self.dossiers.state_not_brouillon.size
  end

  def export_filename(format)
    procedure_identifier = path || "procedure-#{id}"
    "dossiers_#{procedure_identifier}_#{Time.zone.now.strftime('%Y-%m-%d_%H-%M')}.#{format}"
  end

  def export(dossiers)
    ProcedureExportService.new(self, dossiers)
  end

  def to_csv(dossiers)
    export(dossiers).to_csv
  end

  def to_xlsx(dossiers)
    export(dossiers).to_xlsx
  end

  def to_ods(dossiers)
    export(dossiers).to_ods
  end

  def procedure_overview(start_date, groups)
    ProcedureOverview.new(self, start_date, groups)
  end

  def initiated_mail_template
    initiated_mail || Mails::InitiatedMail.default_for_procedure(self)
  end

  def received_mail_template
    received_mail || Mails::ReceivedMail.default_for_procedure(self)
  end

  def closed_mail_template
    closed_mail || Mails::ClosedMail.default_for_procedure(self)
  end

  def refused_mail_template
    refused_mail || Mails::RefusedMail.default_for_procedure(self)
  end

  def without_continuation_mail_template
    without_continuation_mail || Mails::WithoutContinuationMail.default_for_procedure(self)
  end

  def self.default_sort
    {
      'table' => 'self',
      'column' => 'id',
      'order' => 'desc'
    }
  end

  def whitelist!
    update_attribute('whitelisted_at', Time.zone.now)
  end

  def closed_mail_template_attestation_inconsistency_state
    # As an optimization, don’t check the predefined templates (they are presumed correct)
    if closed_mail.present?
      tag_present = closed_mail.body.include?("--lien attestation--")
      if attestation_template&.activated? && !tag_present
        :missing_tag
      elsif !attestation_template&.activated? && tag_present
        :extraneous_tag
      end
    end
  end

  def usual_traitement_time
    percentile_time(:en_construction_at, :processed_at, 90)
  end

  def populate_champ_stable_ids
    TypeDeChamp.where(procedure: self, stable_id: nil).find_each do |type_de_champ|
      type_de_champ.update_column(:stable_id, type_de_champ.id)
    end
  end

  def missing_steps
    result = []

    if service.nil?
      result << :service
    end

    if missing_instructeurs?
      result << :instructeurs
    end

    result
  end

  def move_type_de_champ(type_de_champ, new_index)
    types_de_champ, collection_attribute_name = if type_de_champ.parent&.repetition?
      if type_de_champ.parent.private?
        [type_de_champ.parent.types_de_champ, :types_de_champ_private_attributes]
      else
        [type_de_champ.parent.types_de_champ, :types_de_champ_attributes]
      end
    elsif type_de_champ.private?
      [self.types_de_champ_private, :types_de_champ_private_attributes]
    else
      [self.types_de_champ, :types_de_champ_attributes]
    end

    attributes = move_type_de_champ_attributes(types_de_champ.to_a, type_de_champ, new_index)

    if type_de_champ.parent&.repetition?
      attributes = [
        {
          id: type_de_champ.parent.id,
          libelle: type_de_champ.parent.libelle,
          types_de_champ_attributes: attributes
        }
      ]
    end

    update!(collection_attribute_name => attributes)
  end

  def process_dossiers!
    case declarative_with_state
    when Procedure.declarative_with_states.fetch(:en_instruction)
      dossiers
        .state_en_construction
        .find_each(&:passer_automatiquement_en_instruction!)
    when Procedure.declarative_with_states.fetch(:accepte)
      dossiers
        .state_en_construction
        .find_each(&:accepter_automatiquement!)
    end
  end

  def logo_url
    if logo.attached?
      Rails.application.routes.url_helpers.url_for(logo)
    else
      ActionController::Base.helpers.image_url("marianne.svg")
    end
  end

  def missing_instructeurs?
    !AssignTo.exists?(groupe_instructeur: groupe_instructeurs)
  end

  def routee?
    groupe_instructeurs.count > 1
  end

  def can_be_deleted_by_administrateur?
    brouillon? || dossiers.state_instruction_commencee.empty?
  end

  def can_be_deleted_by_manager?
    kept? && can_be_deleted_by_administrateur?
  end

  def discard_and_keep_track!(author)
    if brouillon?
      reset!
    elsif publiee?
      close!
    end

    dossiers.each do |dossier|
      dossier.discard_and_keep_track!(author, :procedure_removed)
    end

    discard!
  end

  def restore(author)
    if discarded? && undiscard
      dossiers.with_discarded.discarded.find_each do |dossier|
        dossier.restore(author, true)
      end
    end
  end

  def flipper_id
    "Procedure;#{id}"
  end

  private

  def move_type_de_champ_attributes(types_de_champ, type_de_champ, new_index)
    old_index = types_de_champ.index(type_de_champ)
    if types_de_champ.delete_at(old_index)
      types_de_champ.insert(new_index, type_de_champ)
        .map.with_index do |type_de_champ, index|
          {
            id: type_de_champ.id,
            libelle: type_de_champ.libelle,
            order_place: index
          }
        end
    else
      []
    end
  end

  def before_publish
    update!(closed_at: nil, unpublished_at: nil)
  end

  def after_publish(canonical_procedure = nil)
    update!(published_at: Time.zone.now, canonical_procedure: canonical_procedure)
  end

  def after_close
    now = Time.zone.now
    update!(closed_at: now)
  end

  def after_unpublish
    update!(unpublished_at: Time.zone.now)
  end

  def update_juridique_required
    self.juridique_required ||= (cadre_juridique.present? || deliberation.attached?)
    true
  end

  def check_juridique
    if juridique_required? && (cadre_juridique.blank? && !deliberation.attached?)
      errors.add(:cadre_juridique, " : veuillez remplir le texte de loi ou la délibération")
    end
  end

  def percentile_time(start_attribute, end_attribute, p)
    times = dossiers
      .where.not(start_attribute => nil, end_attribute => nil)
      .where(end_attribute => 1.month.ago..Time.zone.now)
      .pluck(start_attribute, end_attribute)
      .map { |(start_date, end_date)| end_date - start_date }

    if times.present?
      times.percentile(p).ceil
    end
  end

  def ensure_path_exists
    if self.path.blank?
      self.path = SecureRandom.uuid
    end
  end

  def ensure_default_groupe_instructeur
    if self.groupe_instructeurs.empty?
      groupe_instructeurs.create(label: GroupeInstructeur::DEFAULT_LABEL)
    end
  end
end
