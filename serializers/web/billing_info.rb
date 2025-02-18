# frozen_string_literal: true

require "countries"

class Serializers::Web::BillingInfo < Serializers::Base
  def self.base(bi)
    {
      id: bi.id,
      ubid: bi.ubid,
      name: bi.stripe_data["name"],
      email: bi.stripe_data["email"],
      address: [bi.stripe_data["address"]["line1"], bi.stripe_data["address"]["line2"]].compact.join(" "),
      country: bi.stripe_data["address"]["country"],
      city: bi.stripe_data["address"]["city"],
      state: bi.stripe_data["address"]["state"],
      postal_code: bi.stripe_data["address"]["postal_code"]
    }
  end

  structure(:default) do |bi|
    base(bi)
  end
end
