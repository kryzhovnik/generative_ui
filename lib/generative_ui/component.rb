# frozen_string_literal: true

module GenerativeUI
  Component = Data.define(:id, :name, :attributes) do
    def self.from_raw(raw)
      raw = {} unless raw.is_a?(Hash)
      id = raw["id"] || raw[:id]
      name = raw["component"] || raw[:component]
      attributes = raw.each_with_object({}) do |(key, value), memo|
        next if %w[id component].include?(key.to_s)

        memo[key.to_s] = value
      end

      new(id:, name:, attributes:)
    end

    def to_h
      { "id" => id, "component" => name, **attributes }
    end
  end
end
