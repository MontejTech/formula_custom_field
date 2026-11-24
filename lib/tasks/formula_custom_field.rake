namespace :redmine do
  namespace :formula_custom_field do
    desc 'Recalculate stored values of formula custom fields. Optional: FIELD_ID=12'
    task recompute: :environment do
      fields = CustomField.where(is_formula: true)
      fields = fields.where(id: ENV['FIELD_ID']) if ENV['FIELD_ID'].present?

      fields.group_by(&:type).each do |type, group|
        klass = group.first.class.customized_class
        puts "#{type}: #{klass.count} objects, #{group.size} formula field(s)"
        wanted = group.map(&:id)

        klass.find_each do |obj|
          values = FormulaCustomField::Calculator.new(obj).compute.slice(*wanted)
          values.each do |field_id, value|
            cv = CustomValue.find_or_initialize_by(
              customized_type: obj.class.base_class.name, customized_id: obj.id, custom_field_id: field_id
            )
            next if cv.persisted? && cv.value.to_s == value.to_s

            cv.value = value
            cv.save(validate: false) # no callbacks on the issue itself: updated_on / journals stay untouched
          end
        end
      end
      puts 'Done.'
    end
  end
end
