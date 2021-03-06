#!/usr/bin/env ruby -w
#
#  Copyright (c) 2007 Ritchie Young. All rights reserved.
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
require 'ruby_sync/connectors/ldap_changelog_connector'
require 'ruby_sync/connectors/memory_connector'


class ChangeLogConnector < RubySync::Connectors::LdapChangelogConnector
  
    # ApacheDS config
    host          'localhost'
    port          10389
    username      'uid=admin,ou=system'
    password      'secret'
    changelog_dn 'cn=changelog,ou=system'
    search_filter Net::LDAP::Filter.pres(:cn)
    search_base   "ou=users,ou=system"

#  # OpenLDAP config
#  host          'localhost'
#  port          389
#  username      'cn=admin,dc=localhost'
#  password      'secret'
#  changelog_dn 'cn=changelog'
#  search_filter Net::LDAP::Filter.pres(:cn)
#  search_base   "dc=localhost"

  # Default config
#  host        'changelog_ldap'
#  port        389
#  username    'cn=directory manager'
#  password    'password'
#  changelog_dn 'cn=changelog'
#  search_filter Net::LDAP::Filter.pres(:cn)
#  search_base   "ou=people,dc=9to5magic,dc=com,dc=au"
end

class TcLdapChangelog <  Test::Unit::TestCase

  include RubySyncTest

  def setup
  end
  
  def teardown
  end

  # Add various types of record and verifies that the appropriate
  # changelog entries appear.
  # Other activity on the LDAP server may interfere with this test.
  def test_get_changes
    banner "test_get_changes"
    c = ChangeLogConnector.new
    path = "cn=bob,#{c.search_base}"
    c.delete(path) if c[path]
    c.each_change do |event|
    end # Ignore up til now

  
    c.add(path, c.create_operations_for(ldap_attr))
    assert_event :add, c, path
  
    c.modify(path, [
      RubySync::Operation.replace('mail', "bob@fischer.com"),
      RubySync::Operation.add('givenName', "Robert")
      ])
    event = assert_event :modify, c, path
    puts event.payload.inspect
  
    c.delete(path)
    assert_event :delete, c, path
  end
  
private

  def ldap_attr
    {
      "objectclass"=>['inetOrgPerson'],
      "cn"=>'bob',
      "sn"=>'roberts',
      "mail"=>"bob@roberts.com"
    }
  end
  
  def assert_event type, connector, path
    events = 0
    the_event=nil
    connector.each_change do |event|
      the_event = event
      events += 1
      assert_equal type.to_sym, event.type
      assert_equal connector, event.source
      assert_equal path, event.source_path
    end
    assert_equal 1, events, "wrong number of events on #{type.to_s}"
    the_event
  end  
  
end