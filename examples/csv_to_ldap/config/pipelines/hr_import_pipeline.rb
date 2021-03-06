class HrImportPipeline < RubySync::Pipelines::BasePipeline

  client :hr

  vault :ldap_vault

  # Remove any fields that you don't want to set in the vault from the client
  allow_in 'id', 'first_name', 'last_name', 'skills'

  # "in" means going from client to vault
  in_event_transform do
    map :cn, 'id'
    map :sn, 'last_name'
    map :givenname, 'first_name'
    map(:employeetype) { value_of('skills').split(':') }
    drop_changes_to 'skills'
    map(:objectclass) { %w(inetOrgPerson organizationalPerson person top) }
  end

  # Should evaluate to the path for placing a new record on the vault
  in_place do
    #"cn=#{source_path},dc=localhost"#OpenLDAP
    "cn=#{source_path},ou=users,ou=system"#ApacheDS
  end

  dump_after :in_event_transform

end
