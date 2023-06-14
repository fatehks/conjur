# frozen_string_literal: true
require 'cucumber/_common/slosilo_helper'

Before('@skip') do
  skip_this_scenario
end

# Reset the DB between each test
#
# Prior to this hook, our tests had hidden coupling.  This ensures each test is
# run independently.
Before do
  @user_index = 0
  @host_index = 0

  Role.truncate(cascade: true)
  Secret.truncate
  Credentials.truncate
  init_slosilo_keys

  Account.find_or_create_accounts_resource
  admin_role = Role.create(role_id: "cucumber:user:admin")
  creds = Credentials.new(role: admin_role)
  # TODO: Replace this hack with a refactoring of policy/api/authenticators to
  #       share this code, and to it the api way (probably)
  creds.password = 'SEcret12!!!!'
  creds.save(raise_on_save_failure: true)

  # Save env to revert to it after the test
  @env = {}
  ENV.each do |key, value|
    @env[key] = value
  end

  # Create a new Scenario Context to use for sharing
  # data between scenario steps.
  @scenario_context = Utilities::ScenarioContext.new
end

After do
  # Reset scenario context
  @scenario_context.reset!

  # Revert to original env
  @env.each do |key, value|
    ENV[key] = value
  end
end
