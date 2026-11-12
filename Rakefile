# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "spec"
  task.pattern = "spec/**/*_spec.rb"
  task.warning = false
end

task default: :test
