class AddFormulaToCustomFields < ActiveRecord::Migration[6.1]
  def change
    add_column :custom_fields, :is_formula, :boolean, default: false, null: false
    add_column :custom_fields, :formula_expression, :text
  end
end
