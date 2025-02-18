# frozen_string_literal: true

require "yaml"

class BillingRate
  def self.rates
    @@rates ||= YAML.load_file("config/billing_rates.yml")
  end

  def self.from_resource_properties(resource_type, resource_family, location)
    rates.find {
      _1["resource_type"] == resource_type && _1["resource_family"] == resource_family && _1["location"] == location
    }
  end

  def self.from_id(billing_rate_id)
    rates.find { _1["id"] == billing_rate_id }
  end
end
