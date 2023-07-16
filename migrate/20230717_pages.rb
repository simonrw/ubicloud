# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:page) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      column :created_at, :timestamptz
      column :resolved_at, :timestamptz
      column :summary, :text, collate: '"C"'
    end
  end
end
