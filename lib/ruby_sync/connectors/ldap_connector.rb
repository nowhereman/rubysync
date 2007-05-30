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


lib_path = File.dirname(__FILE__) + '/..'
$:.unshift lib_path unless $:.include?(lib_path) || $:.include?(File.expand_path(lib_path))

require 'ruby_sync'

$VERBOSE = false
require 'net/ldap'
#$VERBOSE = true

class Net::LDAP::Entry
  def to_hash
    return @myhash.dup
  end
end

module RubySync::Connectors
  class LdapConnector < RubySync::Connectors::BaseConnector
    
    attr_accessor :host, :port, :bind_method, :username, :password,
                  :search_filter, :search_base,
                  :association_attribute # name of the attribute in which to store the association key(s)
    
    def started
      #TODO: If vault, check the schema to make sure that the association_attribute is there
      @association_attribute ||= 'RubySyncAssociation'
    end
    
    def check
      Net::LDAP.open(:host=>@host, :port=>@port, :auth=>auth) do |ldap|
        ldap.search :base => @search_base, :filter => @search_filter do |entry|
          operations = operations_for_entry(entry)
          association_key = (is_vault?)? nil : entry.dn
          yield RubySync::Event.add(self, entry.dn, association_key, operations)
        end
      end
    end
    
    # Runs the query specified by the config, gets the objectclass of the first
    # returned object and returns a list of its allowed attributes
    def self.fields
      log.warn "Fields method not yet implemented for LDAP - Sorry."
      log.warn "Returning a likely sample set."
      %w{ cn givenName sn }
    end

    
    def stopped
    end
    
    def initialize options
      super options
      @bind_method ||= :simple
      @host ||= 'localhost'
      @port ||= 389
      @search_filter ||= "cn=*"
    end


    def self.sample_config
      return <<END
  options(
   :host=>'localhost',
   :port=>10389,
   :username=>'uid=admin,ou=system',
   :password=>'secret',
   :search_filter=>"cn=*",
   :search_base=>"dc=example,dc=com"
  # :bind_method=>:simple,
  )
END
    end



    def add(path, operations)
      with_ldap do |ldap|
        return false unless ldap.add :dn=>path, :attributes=>perform_operations(operations)
      end
      return true
    rescue Net::LdapException
      log.warning "Exception occurred while adding LDAP record"
      false
    end

    def modify(path, operations)
      log.debug "Modifying #{path} with the following operations:\n#{operations.inspect}"
      with_ldap {|ldap| ldap.modify :dn=>path, :operations=>to_ldap_operations(operations) }
    end

    def delete(path)
      with_ldap {|ldap| ldap.delete :dn=>path }
    end

    def [](path)
      with_ldap do |ldap|
        result = ldap.search :base=>path, :scope=>Net::LDAP::SearchScope_BaseObject, :filter=>'objectclass=*'
        return nil if !result or result.size == 0
        result[0].to_hash
      end
    end
    
    def target_transform event
      event.add_default 'objectclass', 'inetOrgUser'
      # TODO: Add modifier and timestamp unless LDAP dir does this automatically
    end

    def associate_with_foreign_key key, path
      with_ldap do |ldap|
        ldap.add_attribute(path, @association_attribute, key.to_s)
      end
    end
    
    def path_for_foreign_key key
      entry = entry_for_foreign_key key
      (entry)? entry.dn : nil
    end
    
    def foreign_key_for path
        entry = self[path]
        (entry)? entry.dn : nil # TODO: That doesn't look right. Should return an association key, not a path.
    end

    def remove_foreign_key key
      with_ldap do |ldap|
        entry = entry_for_foreign_key key
        if entry
          modify :dn=>entry.dn, :operations=>[ [:delete, @association_attribute, key] ]
        end
      end
    end

    def find_associated foreign_key
      entry = entry_for_foreign_key key
      (entry)? operations_for_entry(entry) : nil
    end
    

private

    def operations_for_entry entry
      # TODO: This could probably be done better by mixing Enumerable into Entry and then calling collect
      ops = []
      entry.each do |name, values|
        ops << RubySync::Operation.add(name, values)
      end
      ops
    end

    def entry_for_foreign_key key
      with_ldap do |ldap|
        result = ldap.search :base=>@search_base, :filter=>"#{@association_attribute}=#{key}"
        return nil if !result or result.size == 0
        result[0]
      end
    end


    def with_ldap
      result = nil
      Net::LDAP.open(:host=>@host, :port=>@port, :auth=>auth) do |ldap|
        result = yield ldap
      end
      result
    end
    
    def auth
      {:method=>@bind_method, :username=>@username, :password=>@password}
    end
    
    # Produce an array of operation arrays suitable for the LDAP library
    def to_ldap_operations operations
      operations.map {|op| [op.type, op.subject, op.values]}
    end
    
  end
end