# frozen_string_literal: true

class Serializers::Web::Invoice < Serializers::Base
  def self.base(inv)
    {
      ubid: inv.ubid,
      path: inv.path,
      name: inv.begin_time.strftime("%B %Y"),
      date: inv.created_at.strftime("%B %d, %Y"),
      subtotal: "$%0.02f" % inv.content["cost"],
      total: "$%0.02f" % inv.content["cost"],
      status: inv.status,
      billing_name: inv.content.dig("billing_info", "name"),
      billing_address: inv.content.dig("billing_info", "address"),
      billing_country: ISO3166::Country.new(inv.content.dig("billing_info", "country")).common_name,
      billing_city: inv.content.dig("billing_info", "city"),
      billing_state: inv.content.dig("billing_info", "state"),
      billing_postal_code: inv.content.dig("billing_info", "postal_code"),
      items: inv.content["resources"].flat_map do |resource|
        resource["line_items"].map do |line_item|
          {
            name: resource["resource_name"],
            description: line_item["description"],
            duration: line_item["duration"].to_i,
            cost: (line_item["cost"] < 0.001) ? "less than $0.001" : "$%0.03f" % line_item["cost"]
          }
        end
      end.sort_by { _1[:description] }
    }
  end

  structure(:default) do |inv|
    base(inv)
  end
end
