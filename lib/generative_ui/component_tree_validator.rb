# frozen_string_literal: true

module GenerativeUI
  class ComponentTreeValidator
    Result = Data.define(:valid, :errors) do
      alias_method :valid?, :valid
    end

    TREE_KEY = '_tree'
    MAX_COMPONENTS = 500
    MAX_DEPTH = 64
    MAX_REFS = 2_000

    def self.call(component_set, catalog:)
      new(component_set, catalog).call
    end

    def initialize(component_set, catalog)
      @component_set = component_set
      @catalog = catalog
      @errors = {}
      @edges = Hash.new { |hash, key| hash[key] = [] }
    end

    def call
      validate_admission_limits
      return Result.new(valid: false, errors:) if errors.any?

      validate_components
      validate_structure
      Result.new(valid: errors.empty?, errors:)
    end

    private

    attr_reader :component_set, :catalog, :errors, :edges

    def validate_admission_limits
      tree_error("component limit exceeded (max #{MAX_COMPONENTS})") if component_set.components.size > MAX_COMPONENTS
    end

    def validate_components
      component_set.components.each do |component|
        result = ComponentValidator.call(component, catalog:)
        result.errors.each { |message| component_error(component.id || '_component', message) } unless result.valid?
      end
    end

    def validate_structure
      component_set.duplicate_ids.each { |id| tree_error("duplicate component id '#{id}'") }
      return tree_error('root component not found') unless component_set.root

      collect_edges
      walk_from_root
      report_orphans
    end

    def collect_edges
      @parents = {}
      @ref_count = 0

      component_set.components.each do |component|
        definition = catalog.fetch(component.name)
        next unless definition

        definition.structural_refs.each do |ref|
          extract_refs(component.attributes, ref.path).each do |field_path, child_id|
            @ref_count += 1
            tree_error("reference limit exceeded (max #{MAX_REFS})") if @ref_count == MAX_REFS + 1
            source = "#{component.id}.#{field_path}"
            validate_reference(component, ref, source, child_id)
          end
        end
      end
    end

    def validate_reference(component, ref, source, child_id)
      target = component_set.by_id[child_id]
      return relation_error(source, "referenced component '#{child_id}' not found") unless target

      if ref.only.present? && !ref.only.include?(target.name)
        relation_error(source, "expected #{ref.only.join(' or ')}, got #{target.name}")
      end

      if (existing_parent = @parents[child_id])
        tree_error("component '#{child_id}' referenced by both '#{existing_parent}' and '#{source}'")
      else
        @parents[child_id] = source
      end

      edges[component.id] << child_id
    end

    def extract_refs(value, path, rendered_path = [])
      return [] if path.empty?

      segment, *rest = path
      if segment == :*
        return [] unless value.is_a?(Array)

        return value.each_with_index.flat_map do |item, index|
          extract_refs(item, rest, rendered_path + [index])
        end
      end

      return [] unless value.is_a?(Hash)

      child = value[segment.to_s] || value[segment.to_sym]
      current_path = rendered_path + [segment]

      if rest.empty?
        return child.map { |child_id| [format_path(current_path), child_id] } if child.is_a?(Array)

        return child.nil? ? [] : [[format_path(current_path), child]]
      end

      extract_refs(child, rest, current_path)
    end

    def walk_from_root
      @visited = Set.new
      @in_progress = []
      walk('root', 1)
    end

    def walk(id, depth)
      if depth > MAX_DEPTH
        tree_error("tree depth limit exceeded (max #{MAX_DEPTH})")
        return
      end

      if @in_progress.include?(id)
        cycle_start = @in_progress.index(id)
        path = @in_progress[cycle_start..] + [id]
        tree_error("cycle: #{path.join(' → ')}")
        return
      end

      return if @visited.include?(id)

      @in_progress << id
      edges[id].each { |child_id| walk(child_id, depth + 1) }
      @in_progress.pop
      @visited << id
    end

    def report_orphans
      (component_set.ids.compact.uniq - @visited.to_a).each do |id|
        tree_error("orphan component '#{id}'")
      end
    end

    def format_path(parts)
      parts.each_with_object(+'') do |part, rendered|
        if part.is_a?(Integer)
          rendered << "[#{part}]"
        else
          rendered << '.' unless rendered.empty?
          rendered << part.to_s
        end
      end
    end

    def tree_error(message)
      (errors[TREE_KEY] ||= []) << message
    end

    def component_error(id, message)
      (errors[id] ||= []) << message
    end

    def relation_error(path, message)
      (errors[path] ||= []) << message
    end
  end
end
