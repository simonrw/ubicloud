# frozen_string_literal: true

require "time"

class InvoiceGenerator
  def initialize(begin_time, end_time, save_result = false)
    @begin_time = begin_time
    @end_time = end_time
    @save_result = save_result
  end

  def run
    invoices = []

    DB.transaction do
      active_billing_records.group_by { |br| br[:project_id] }.each do |project_id, project_records|
        project_content = {}
        project_content[:project_id] = project_id
        project_content[:project_name] = project_records.first[:project_name]
        project_content[:billing_info] = project_records.first[:billing_info]

        project_content[:resources] = []
        project_content[:cost] = 0
        project_records.group_by { |pr| pr[:resource_id] }.each do |resource_id, line_items|
          resource_content = {}
          resource_content[:resource_id] = resource_id
          resource_content[:resource_name] = line_items.first[:resource_name]

          resource_content[:line_items] = []
          resource_content[:cost] = 0
          line_items.each do |li|
            line_item_content = {}
            line_item_content[:location] = li[:location]
            line_item_content[:resource_type] = li[:resource_type]
            line_item_content[:resource_family] = li[:resource_family]
            line_item_content[:description] = BillingRate.line_item_description(li[:resource_type], li[:resource_family], li[:amount])
            line_item_content[:amount] = li[:amount].to_f
            line_item_content[:duration] = li[:duration]
            line_item_content[:cost] = li[:cost].to_f

            resource_content[:line_items].push(line_item_content)
            resource_content[:cost] += line_item_content[:cost].to_f
          end

          project_content[:resources].push(resource_content)
          project_content[:cost] += resource_content[:cost].to_f
        end

        invoices.push(project_content)

        if @save_result
          Invoice.create_with_id(project_id: project_id, content: project_content, begin_time: @begin_time, end_time: @end_time)
        end
      end
    end

    invoices
  end

  def active_billing_records
    active_billing_records = BillingRecord.eager(project: :billing_info)
      .where { |br| Sequel.pg_range(br.span).overlaps(Sequel.pg_range(@begin_time...@end_time)) }
      .all

    active_billing_records.map do |br|
      {
        project_id: br.project_id,
        project_name: br.project.name,
        resource_id: br.resource_id,
        location: br.billing_rate["location"],
        resource_name: br.resource_name,
        resource_type: br.billing_rate["resource_type"],
        resource_family: br.billing_rate["resource_family"],
        amount: br.amount,
        duration: br.duration(@begin_time, @end_time).ceil,
        cost: (br.amount * br.duration(@begin_time, @end_time) * br.billing_rate["unit_price"]),
        billing_info: br.project.billing_info ? Serializers::Web::BillingInfo.serialize(br.project.billing_info) : nil
      }
    end
  end
end
