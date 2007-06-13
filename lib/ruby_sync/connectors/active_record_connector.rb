#!/usr/bin/env ruby
#
#  Copyright (c) 2007 Ritchie Young. All rights reserved.
#
# This file is part of RubySync.
# 
# RubySync is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.
# 
# RubySync is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along with RubySync; if not, write to the
# Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA

require 'erb'
$VERBOSE=false
require "active_record"
#$VERBOSE=true
require "ruby_sync/connectors/base_connector"


module RubySync::Connectors

  # You can initialize this connector with the name of a model and the path to a rails application:
  # eg: vault :ActiveRecord, :application=>'path/to/rails/application', :model=>:user
  class ActiveRecordConnector < RubySync::Connectors::BaseConnector


    option :ar_class, :model, :application, :rails_env, :db_type, :db_host, :db_name, :db_config
    rails_env 'development'
    db_type 'mysql'
    db_host 'localhost'
    db_name "rubysync_#{get_rails_env}"
    # Default db_config in case we're not sucking the config out of a rails app
    db_config(
      :adapter=>get_db_type,
      :host=>get_db_host,
      :database=>get_db_name
    )
    model :user


    def initialize options={}
      super options

      # Rails app specified, use it to configure
      if application
        # Load the database configuration
        rails_app_path = File.expand_path(application, File.dirname(__FILE__))
        db_config_filename = File.join(rails_app_path, 'config', 'database.yml')
        db_config = YAML::load(ERB.new(IO.read(db_config_filename)).result)[rails_env]
        # Require the models
        log.debug "Loading the models for #{self.class.name}:"
        Dir.chdir(File.join(rails_app_path,'app','models')) do
          Dir.glob('*.rb') do |filename|
            log.debug("\t#{filename}")
            require filename
            class_name = filename[0..-4].camelize
            klass = class_name.constantize
            klass.establish_connection db_config if defined? klass.establish_connection
          end
        end
      end

      self.class.ar_class model.to_s.camelize.constantize
    end

      
      def self.fields
        c = self.new
        c.ar_class.content_columns.map {|col| col.name }
      end
      
      def self.sample_config
          return <<END

    application '/path/to/a/rails/application'
    model 'name_of_model_to_sync'

END
      end
      
      
    # Process each RubySyncEvent and then delete it from the db.
    def each_change
      ::RubySyncEvent.find(:all).each do |rse|
        event = RubySync::Event.new(rse.event_type, self, rse.trackable_id, nil, to_payload(rse))
        yield event
        ::RubySyncEvent.delete rse
      end
    end

    # Create a hash suitable to use as rubysync event payload
    def to_payload ar_event
      ar_event.operations.map do |op|
        RubySync::Operation.new(op.operation.to_sym, op.field_name, op.values.map {|v| v.value})
      end
    end

    # Override default perform_add because ActiveRecord is different in that
    # the target path is ignored when adding a record. ActiveRecord determines
    # the id on creation.
    def perform_add event
      log.info "Adding '#{event.target_path}' to '#{name}'"
      ar_class.new() do |record|
        populate(record, perform_operations(event.payload))
        log.info(record.inspect)
        record.save!
        if is_vault?
          associate event.association, record.id
        end
        record.id
      end
    rescue => ex
      log.warn ex
      #puts ex.backtrace.join("\n")
      return nil
    end

      
    def modify(path, operations)
      ar_class.find(path) do |record|
        populate(record, perform_operations(operations))
        record.save
      end
    end
    
    def delete(path)
      ar_class.destroy path
    end
  
    # Implement vault functionality

    def associate association, path
      log.debug "Associating '#{association}' with '#{path}'"
      ruby_sync_association.create :synchronizable_id=>path, :synchronizable_type=>ar_class.name,
                                   :context=>association.context, :key=>association.key
    end

    def find_associated association
      ruby_sync_association.find_by_context_and_key association.context, association.key
    end

    def path_for_association association
      assoc = ruby_sync_association.find_by_context_and_key association.context, association.key
      (assoc)? assoc.synchronizable_id : nil
    end

    def association_key_for context, path
      record = ruby_sync_association.find_by_synchronizable_id_and_synchronizable_type_and_context path, model.to_s, context
      record and record.key
    end
    
    def associations_for(path)
      ruby_sync_association.find_by_synchronizable_id_and_synchronizable_type(path, model.to_s)
    rescue ActiveRecord::RecordNotFound
      return nil
    end
    
    def remove_association association
       ruby_sync_association.find_by_context_and_key(association.context, association.key).destroy
    rescue ActiveRecord::RecordNotFound
       return nil
    end


    def [](path)
      ar_class.find(path)
    rescue ActiveRecord::RecordNotFound
      return nil
    end

private

    def ruby_sync_association
      unless @ruby_sync_association
        @ruby_sync_association = ::RubySyncAssociation
        ::RubySyncAssociation.establish_connection(db_config)
      end
      @ruby_sync_association
    end

    def populate record, content
      ar_class.content_columns.each do |c|
        record[c.name] = content[c.name][0] if content[c.name]
      end
    end

    def create_operations_for_active_record record
      operations = record.class.content_columns.map do |col|
        key = col.name
        value = record.send key
        RubySync::Operation.new(:add, key.to_s, value) if key and value
      end
      operations.compact
    end
  end
end
