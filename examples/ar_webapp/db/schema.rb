# This file is autogenerated. Instead of editing this file, please use the
# migrations feature of ActiveRecord to incrementally modify your database, and
# then regenerate this schema definition.

ActiveRecord::Schema.define(:version => 4) do

  create_table "association_keys", :force => true do |t|
    t.column "pipeline",            :string
    t.column "value",               :string
    t.column "synchronizable_id",   :integer
    t.column "synchronizable_type", :string
  end

  add_index "association_keys", ["pipeline", "value"], :name => "index_association_keys_on_pipeline_and_value", :unique => true
  add_index "association_keys", ["synchronizable_id"], :name => "index_association_keys_on_synchronizable_id"

  create_table "hobbies", :force => true do |t|
    t.column "name", :string
  end

  create_table "interests", :force => true do |t|
    t.column "person_id", :integer
    t.column "hobby_id",  :integer
  end

  create_table "people", :force => true do |t|
    t.column "first_name", :string
    t.column "last_name",  :string
  end

end
