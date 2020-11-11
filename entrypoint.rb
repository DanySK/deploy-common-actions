#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'

require 'yaml'
require 'git'
require 'octokit'

puts 'Computing workspace directory'
workspace = ENV['GITHUB_WORKSPACE'] || raise('Mandatory GITHUB_WORKSPACE environment variable unset')
Dir.empty?(workspace) || raise("#{workspace} not empty. Terminating to prevent unexpected side effects.")
puts "Detected workspace: #{workspace}"

github_user = ARGV[1] || ENV['GITHUB_ACTOR'] || raise("User required, no user specified.")
github_token = ARGV[0] || raise('No GitHub token provided')
puts "Configured user #{github_user}, authorizing Octokit..."
client = Octokit::Client.new(:access_token => github_token)

puts 'Setting up a clone of the configuration'
github_server = ENV['GITHUB_SERVER_URL'] || 'https://github.com'
origin_repo = ENV['GITHUB_REPOSITORY'] || raise('Mandatory GITHUB_REPOSITORY environment variable unset')
reference_clone_uri = "#{github_server}/#{origin_repo}"
source_folder = "#{workspace}/#{origin_repo}"
puts "Cloning from #{reference_clone_uri}"
origin_git = Git.clone(reference_clone_uri, source_folder)
origin_sha = origin_git.object('HEAD').sha[0,7]
puts 'Clone complete'

puts "Loading configuration"
config_file = ARGV[2] || 'auto-delivery.yml'
config_path = "#{source_folder}/#{config_file}"
puts "Looking for file #{config_path}"
configuration = YAML.load_file("#{config_path}")

puts 'Processing deliveries'
sources = configuration.keys
puts "This configuration contains #{sources.size} deliveries"

def arrayfy(object)
    object.kind_of?(Array) ? object : [object]
end

sources.each do | delivery |
    puts "Delivering #{delivery}"
    delivery_source_folder = "#{source_folder}/#{delivery}/."
    owners = arrayfy(configuration[delivery]) # array of owners
    owners.each do | owner_configuration | # single entry hash or string
        if owner_configuration.kind_of?(Hash) then # single-entry hash
            if owner_configuration.size == 1 then
                owner = owner_configuration.first.first
                puts "Sending #{delivery} to #{owner}'s configured repositories'"
                repositories = arrayfy(owner_configuration.first[1])
                repositories.each do | repository_configuration | # either string or hash
                    repository = repository_configuration.kind_of?(Hash) ? repository_configuration.first.first : repository_configuration
                    branches = arrayfy(repository_configuration.kind_of?(Hash) ? repository_configuration.first[1] : 'master')
                    branches.each do | branch |
                        unless branch.kind_of?(String) then
                            raise "#{branch} is not a valid branch descriptor, expected a String"
                        end
                        repo_slug = "#{owner}/#{repository}"
                        puts "Delivering to #{repo_slug}:#{branch}"
                        clone_url = "#{github_server}/#{repo_slug}"
                        destination = "#{workspace}/#{repo_slug}"
                        git = Git.clone(clone_url, destination)
                        git.checkout(branch)
                        head_branch = "auto_delivery_from_#{origin_repo}@#{origin_sha}"
                        git.branch(head_branch).checkout
                        FileUtils.cp_r(delivery_source_folder, destination)
                        git.add('.')
                        if git.status.added.empty? then
                            puts 'No change w.r.t. the current status'
                        else
                            message = "Automatic delivery from #{origin_repo}@#{origin_sha}"
                            git.commit(message)
                            remote_uri = "https://#{github_user}:#{github_token}@#{github_server.split('://').last}/#{repo_slug}"
                            authenticated_remote_name = 'authenticated'
                            git.add_remote(authenticated_remote_name, remote_uri)
                            git.push(authenticated_remote_name, head_branch)
                            client.create_pull_request(repo_slug, branch, head_branch, message)
                        end
                    end
                end
            else
                puts "Unexpected owner configuration #{owner_configuration}, Hash has multiple values"
            end
        else
            puts "#{owner_configuration} not a Ruby Hash, skipping"
        end
    end
end

puts 'Cleaning the workspace directory'
FileUtils.rm_rf(Dir["#{workspace}/*"])
puts 'Done'
