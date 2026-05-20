# frozen_string_literal: true

module GenerativeUI
  class ComponentSet
    attr_reader :components

    def self.from_args(raw_components)
      new(Array(raw_components).map { |raw| Component.from_raw(raw) })
    end

    def initialize(components)
      @components = components
    end

    def by_id
      @by_id ||= components.each_with_object({}) do |component, index|
        index[component.id] ||= component
      end
    end

    def root
      by_id["root"]
    end

    def fetch(id)
      by_id.fetch(id)
    end

    def ids
      components.map(&:id)
    end

    def duplicate_ids
      ids.compact.group_by(&:itself).select { |_id, entries| entries.size > 1 }.keys
    end
  end
end
