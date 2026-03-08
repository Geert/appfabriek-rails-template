class Identity < ApplicationRecord
  has_many :magic_links, dependent: :destroy
  has_many :sessions, dependent: :destroy

  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }
  normalizes :email_address, with: ->(value) { value.strip.downcase.presence }

  def send_magic_link(**attributes)
    attributes[:purpose] = attributes.delete(:for) if attributes.key?(:for)

    magic_links.create!(attributes).tap do |magic_link|
      MagicLinkMailer.sign_in_instructions(magic_link).deliver_later
    end
  end
end
