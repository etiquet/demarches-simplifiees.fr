class Champs::DateChamp < Champ
  before_save :format_before_save

  def search_terms
    # Text search is pretty useless for dates so we’re not including these champs
  end

  def to_s
    value.present? ? I18n.l(Time.zone.parse(value), format: '%d %B %Y') : ""
  end

  def for_tag
    value.present? ? I18n.l(Time.zone.parse(value), format: '%d %B %Y') : ""
  end

  private

  def format_before_save
    self.value =
      begin
        Time.zone.parse(value).to_date.iso8601
      rescue
        nil
      end
  end
end
