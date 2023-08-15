# frozen_string_literal: true

require_relative "../model"

class Invoice < Sequel::Model
  include ResourceMethods

  def path
    "/invoice/#{ubid}"
  end
end
