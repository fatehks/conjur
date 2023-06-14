# frozen_string_literal: true

# Generates random unique names
#
require 'haikunator'
require 'fileutils'
require 'cucumber/_common/slosilo_helper'

Before do |scenario|
  @scenario_name = scenario.name
end

Before "@echo" do |scenario|
  @echo = true
end

# Reset the DB between each test
#
# Prior to this hook, our tests had hidden coupling.  This ensures each test is
# run independently.
Before do
  @user_index = 0

  Role.truncate(cascade: true)
  Secret.truncate
  Credentials.truncate

  init_slosilo_keys
  
  Account.find_or_create_accounts_resource
  admin_role = Role.create(role_id: "cucumber:user:admin")
  creds = Credentials.new(role: admin_role)
  # TODO: Replace this hack with a refactoring of policy/api/authenticators to share
  # this code, and to it the api way (probably)
  creds.password = 'SEcret12!!!!'
  creds.save(raise_on_save_failure: true)

  # Save env to revert to it after the test
  @env = {}
  ENV.each do |key, value|
    @env[key] = value
  end
end

After do
  # Revert to original env
  @env.each do |key, value|
    ENV[key] = value
  end
end
