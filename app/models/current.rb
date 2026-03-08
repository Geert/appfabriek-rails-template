class Current < ActiveSupport::CurrentAttributes
  attribute :session, :identity, :account
  attribute :http_method, :request_id, :user_agent, :ip_address

  def session=(value)
    super(value)
    self.identity = value&.identity
  end

  def with_account(value, &)
    with(account: value, &)
  end
end
