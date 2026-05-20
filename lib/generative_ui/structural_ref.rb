# frozen_string_literal: true

module GenerativeUI
  StructuralRef = Data.define(
    :path,
    :cardinality,
    :required,
    :only,
    :description,
    :min_items,
    :max_items
  )
end
