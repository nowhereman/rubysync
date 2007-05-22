# This file is autogenerated. Instead of editing this file, please use the
# migrations feature of ActiveRecord to incrementally modify your database, and
# then regenerate this schema definition.

ActiveRecord::Schema.define(:version => 4) do

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

  create_table "ruby_sync_associations", :force => true do |t|
    t.column "context",             :string
    t.column "key",                 :string
    t.column "synchronizable_id",   :integer
    t.column "synchronizable_type", :string
  end

  add_index "ruby_sync_associations", ["context", "key"], :name => "index_ruby_sync_associations_on_context_and_key", :unique => true
  add_index "ruby_sync_associations", ["synchronizable_id"], :name => "index_ruby_sync_associations_on_synchronizable_id"

end