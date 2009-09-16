#!/usr/bin/env ruby -w
#
#  Copyright (c) 2009 Nowhere Man
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


[  File.dirname(__FILE__) + '/../lib', File.dirname(__FILE__)
].each {|path| $:.unshift path unless $:.include?(path) || $:.include?(File.expand_path(path))}


require 'ruby_sync_test'
require 'hashlike_tests'
require 'ruby_sync/connectors/ldap_changelog_ruby_connector'
require 'ruby_sync/connectors/memory_connector'


class MyLdapConnector < RubySync::Connectors::LdapChangelogRubyConnector
   # ApacheDS config
#    host          'localhost'
#    port          10389
#    username      'uid=admin,ou=system'
#    password      'secret'
#    changelog_dn  'cn=changelog,ou=system'
#    search_filter 'cn=*'
#    search_base   'ou=users,ou=system'

  # OpenDS config
    host         'localhost'
    port          1389
    username      'cn=Directory Manager'
    password      'secret'
    changelog_dn  'ou=changelog,dc=example,dc=com'
    search_filter 'cn=*'
    search_base   'ou=People,dc=example,dc=com'

#  # OpenLDAP config
#  host          'localhost'
#  port          389
#  username      'cn=admin,dc=localhost'
#  password      'secret'
#  changelog_dn 'cn=changelog'
#  search_filter 'cn=*'
#  search_base   'dc=localhost'

  # Default config
#  host        '10.1.1.4'
#  port        389
#  username    'cn=directory manager'
#  password    'password'
#  changelog_dn 'cn=changelog'
#  search_filter "cn=*"
#  search_base   "ou=people,dc=9to5magic,dc=com,dc=au"
  
  def initialize options={}
    super(options)
#    skip_existing_changelog_entries
  end

end

class MyMemoryConnector < RubySync::Connectors::MemoryConnector;
end

class LdapSoftwareTestPipeline < RubySync::Pipelines::BasePipeline
  
  client :my_memory

  vault :my_ldap
  
  allow_out :cn, :givenName, :sn, :objectclass
  allow_in :cn, :givenName, :sn, :objectclass
  
  def in_place(event)
#    event.target_path = "cn=#{event.source_path},ou=users,ou=system"#ApacheDS
    event.target_path = "cn=#{event.source_path},ou=People,dc=example,dc=com"#OpenDS
    #event.target_path = "cn=#{event.source_path},dc=localhost"#OpenLDAP
    #event.target_path = "cn=#{event.source_path},ou=people,dc=9to5magic,dc=com,dc=au"#Default
  end
  
  def out_place(event)
    event.target_path = event.source_path.scan(/cn=(.+?),/oi).to_s
   # event.source_path = $1
  end
  
#  in_event_transform do
#    if type == :add or type == :modify
#      each_operation_on('givenName') { |operation| append operation.same_but_on('cn') }
#      append RubySync::Operation.new(:add, 'objectclass', ['inetOrgPerson'])
#    end
#  end
  
end


class TcLdapVaultSoftware < Test::Unit::TestCase

  include RubySyncTest
  include HashlikeTests

  def initialize(test)
    super(test)
    
    # Removing previous LDAP entries
      pipeline = testPipeline.new
      vault = pipeline.vault

      with_ldap(vault) do |ldap|
        filter = Net::LDAP::Filter.eq(RUBYSYNC_LAST_SYNC_ATTRIBUTE, "#{vault.association_context.ldap_encode},*")
        unless (entry = ldap.search(:base => vault.search_base, :filter => filter, :scope => Net::LDAP::SearchScope_BaseObject)).empty?
          entry[0][RUBYSYNC_LAST_SYNC_ATTRIBUTE].each do |last_sync|
            unless last_sync.match(/^#{vault.association_context.ldap_encode},.*$/).nil?
              ldap.delete_value(entry[0].dn, RUBYSYNC_LAST_SYNC_ATTRIBUTE.downcase.to_sym, last_sync)
              break
            end
          end

        end

        ldap.search(:base => vault.changelog_dn, :filter => "objectClass = changeLogEntry") { |entry| ldap.delete(:dn => entry.dn)}
        ldap.search(:base => vault.search_base, :filter => "objectClass = inetOrgPerson") { |entry| ldap.delete(:dn => entry.dn)}
      end
  end
  
  def setup
    super
    @bob_details = {
      "objectclass"=>['inetOrgPerson'],
      "cn"=>['bob'],
      "sn"=>['roberts']
      #"mail"=>['bob@roberts.com']
      }
      
     @joe_details = { :dn =>"cn=joe,#{@vault.search_base}",
      :objectclass => 'inetOrgPerson',
      :cn=>'joe',
      :sn=>'bigjim',
      :mail => 'joe@bigjim.com'
      }
  end

  def testPipeline
    LdapSoftwareTestPipeline
  end

  def unsynchable
    [:objectclass, :interests, :cn, :dn, :rubysyncassociation ]
  end

  def client_path
    'bob'
  end

  def vault_path
#    'cn=bob,ou=users,ou=system'#ApacheDS
    'cn=bob,ou=People,dc=example,dc=com'#OpenDS
    #'cn=bob,dc=localhost'#OpenLDAP
    #'cn=bob,ou=people,dc=9to5magic,dc=com,dc=au'#Default
  end

   def test_client_to_vault
    banner "test_client_to_vault"
    assoc_key = @client.add client_path, @client.create_operations_for(@bob_details)
    assert_not_nil @client.entry_for_own_association_key(assoc_key)
    assert_nil @vault[vault_path], "Vault already contains bob"
    @pipeline.run_once
    assert_not_nil @vault[vault_path], "#{vault_path} wasn't created on the vault"
    assert_equal normalise(@bob_details), normalise(@vault[vault_path].reject {|k,v| ['modifier',:association].include? k})

    add_ldap_entry(@joe_details)
    @pipeline.run_once

    @bob_details['sn']=['robertos']
    @client.modify(client_path, [RubySync::Operation.replace('sn', 'robertos')])
    @pipeline.run_once
    assert_equal @bob_details['sn'].to_s, @vault[vault_path]['sn'].to_s
    
    @client.modify(client_path, [RubySync::Operation.replace('sn', 'robertas'),RubySync::Operation.add('givenName', "Robert")])
    @pipeline.run_once
    assert_equal 'robertas', @vault[vault_path]['sn'].to_s
    @bob_details['sn']=['robertas']
    @bob_details['givenName']=['Robert']

    assert_respond_to @client, :delete
    @client.delete client_path
    assert_equal normalise(@bob_details), normalise(@vault[vault_path].reject {|k,v| ['modifier',:association].include? k})
    assert_nil @client[client_path], "Bob wasn't deleted from the client"
    @pipeline.run_once
    assert_nil @client[client_path], "Bob reappeared on the client"
    assert_nil @vault[vault_path], "Bob wasn't deleted from the vault"
    @pipeline.run_once # run again in case of echoes
    assert_nil @client[client_path], "Bob reappeared on the client"
    assert_nil @vault[vault_path], "Bob reappeared in the vault. He may have been created by an echoed add event"
    
    person = @joe_details.dup
    person[:cn] = 'jojo'
    person[:objectclass] << RUBYSYNC_ASSOCIATION_CLASS
    op1 = [:add, :objectclass, RUBYSYNC_ASSOCIATION_CLASS]
    modify_ldap_entry(person, [op1])
    @pipeline.run_once

    delete_ldap_entry(@joe_details)
    @pipeline.run_once
    with_ldap(@vault) do |ldap|
      assert_equal(true,ldap.search(:base => @vault.search_base, :filter => "(& (cn = #{@bob_details['cn']}) (objectClass = inetOrgPerson))").empty?)
    end
    
  end

  def test_vault
    #super
  end

  def test_vault_to_client
    super
  end

  #Helpers
  
  def add_ldap_entry(entry)
    person = entry.dup
    person_dn = person.delete(:dn)

    with_ldap(@vault) do |ldap|
      ldap.add(:dn => person_dn, :attributes => person)
      filter = Net::LDAP::Filter.pres("objectclass") & Net::LDAP::Filter.eq("cn", person[:cn])
      assert_equal(false,ldap.search(:base => @vault.search_base, :filter => filter).empty?)
    end
  end

  def modify_ldap_entry(entry, operations)
    person = entry.dup
    #person_dn = person.delete(:dn)

    with_ldap(@vault) do |ldap|
      ldap.modify(:dn => person[:dn], :operations => operations)
      filter = Net::LDAP::Filter.pres("objectclass") & Net::LDAP::Filter.eq("cn", person[:cn])
      ldap.search(:base => @vault.search_base, :filter => filter) do |ldap_entry|
        assert_equal(normalise(person[:objectclass]), normalise(ldap_entry.objectclass))
      end
    end
  end

  def delete_ldap_entry(entry)
    with_ldap(@vault) do |ldap|
      ldap.delete(:dn => entry[:dn])
      filter = Net::LDAP::Filter.pres("objectclass") & Net::LDAP::Filter.eq("cn", entry[:cn])
      assert_equal(true,ldap.search(:base => @vault.search_base, :filter => filter).empty?)
    end    
  end

  private

  def with_ldap(connector)
    result = nil
    auth={:method=>connector.bind_method, :username=>connector.username, :password=>connector.password}
    connection_options = {:host=>connector.host, :port=>connector.port, :auth=>auth}
    connection_options[:encryption] = connector.encryption if connector.encryption

    connection = Net::LDAP.new(connection_options)
    if connection
      ldap = connection
      result = yield ldap
    end
    result
  end
end