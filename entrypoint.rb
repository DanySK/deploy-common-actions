#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'

require 'git'
require 'octokit'
require 'rbnacl'
require 'values'
require 'yaml'

# Immutable Delivery type
class Delivery < Value.new(:index, :name, :owner, :repository, :branch)
    def to_s
        "<Delivery #{index}: #{name} to #{owner}/#{repository}@#{branch}>"
    end
end

# Extend Hashes by providing an iterator that interprets them as deliveries
class Hash
    def each_delivery
        each_with_index do | delivery, index |
            def process_owners_hash(owners)
                owners.each do | owner, repositories |
                    case repositories
                    when Hash
                        repositories.each do | repository, branches |
                            # Branches can be Hash, Array, String, or nil
                            actual_branches = branches || 'master'
                            actual_branches = case actual_branches
                                when String
                                    [actual_branches]
                                when Hash
                                    actual_branches.keys
                                when Array
                                    actual_branches
                                else
                                    raise "Expected nil, or String, or Array, or Hash for branches, but got #{branches}"
                                end
                            actual_branches.each do | branch |
                                yield Delivery.new(index, delivery_name, owner, repository, branch)
                            end
                        end
                    when String
                        yield Delivery.new(index, delivery_name, owner, repositories, 'master')
                    else
                        raise "Expected a repositories descriptor (Hash) but got: #{delivery}"
                    end
                end
            end
            def process_owners_list(owners)
                owners.each do | owners_map |
                    process_owners(owners_map)
                end
            end
            def process_owners(owners)
                if owners.kind_of?(Hash)
                    process_owners_hash(owners)
                elsif owner.kind_of?(Array)
                    process_owners_list(owners)
                else
                    raise "Expected an owners descriptor (Hash) but got: #{delivery}"
                end
            end
            if delivery.kind_of?(Array)
                delivery_name = delivery.first
                owners = delivery.last || {}
                process_owners(owners)
            else
                raise "Expected a delivery (2-ple) but got: #{delivery}"
            end
        end
    end
end

# Common configuration
puts 'Checking input parameters'
github_token = ARGV[0] || raise('No GitHub token provided')
if github_token.size < 20 then
    raise "The provided GitHub is just #{github_token.size} characters long, this does not seem right."
end
github_api_endpoint = ENV['GITHUB_API_URL'] || 'https://api.github.com'
puts "Configuring API access, selected endpoint is #{github_api_endpoint}"
Octokit.configure do | conf |
    conf.api_endpoint = github_api_endpoint
end
puts 'Authenticating with GitHub...'
client = Octokit::Client.new(:access_token => github_token)
puts 'Setting up a clone of the configuration'
origin_repo = ENV['GITHUB_REPOSITORY'] || raise('Mandatory GITHUB_REPOSITORY environment variable unset')
puts 'Computing workspace directory'
workspace = ENV['GITHUB_WORKSPACE'] || raise('Mandatory GITHUB_WORKSPACE environment variable unset')
Dir.empty?(workspace) || raise("#{workspace} not empty. Terminating to prevent unexpected side effects.")
source_folder = "#{workspace}/#{origin_repo}"
github_server = ENV['GITHUB_SERVER_URL'] || 'https://github.com'
reference_clone_uri = "#{github_server}/#{origin_repo}"
puts "Cloning from #{reference_clone_uri}"
origin_git = Git.clone(reference_clone_uri, source_folder)
origin_sha = origin_git.object('HEAD').sha[0,7]
puts 'Clone complete'
puts "Loading configuration"
config_file = ARGV[2] || 'auto-delivery.yml'
config_path = "#{source_folder}/#{config_file}"
puts "Looking for file #{config_path}"
configuration = YAML.load_file("#{config_path}")
configuration.kind_of?(Hash) || raise("Configuration is not a Hash: #{configuration}")

# Secrets deliveries
known_keys = {}
secrets_deliveries = configuration['secrets'] || puts('No secrets deliveries') || {}
puts "Secrets to be delivered: #{secrets_deliveries}"
secrets_deliveries.each_delivery do | delivery |
    repo_slug = "#{delivery.owner}/#{delivery.repository}"
    # puts "Loading public key for #{repo_slug}."
    pubkey = known_keys[repo_slug] || client.get_public_key(repo_slug)
    known_keys[repo_slug] = pubkey
    key = Base64.decode64(pubkey.key)
    # puts "Key decoded, preparing encryption box"
    sodium_box = RbNaCl::Boxes::Sealed.from_public_key(key)
    # puts "Box is ready, encrypting"
    encrypted_value = sodium_box.encrypt(
        ENV[delivery.name] || raise("Secret named #{delivery.name} is unavailable as enviroment variable, it can't get pushed anywhere")
    )
    puts "Secret #{delivery.name} encrypted, preparing payload for #{repo_slug}"
    payload = { 'key_id' => pubkey.key_id, 'encrypted_value' => Base64.strict_encode64(encrypted_value) }
    client.create_or_update_secret(repo_slug, delivery.name, payload)
    puts "Secret #{delivery.name} delivered to #{repo_slug}"
end

puts "Secrets deliveries completed"

# File deliveries
file_deliveries = configuration['files'] || puts('No file deliveries') || {}
unless file_deliveries.empty? then
    github_user = ARGV[1] || ENV['GITHUB_ACTOR'] || raise("User required, no user specified.")
    committer = ARGV[3] || 'Autodelivery [bot]'
    email = ARGV[4] || 'autodelivery@autodelivery.bot'    
    labels = (ARGV[5] || '').split(',').map(&:strip)
    color_regex = /(?:[0-F]|[a-f]){6}/
    colors = (ARGV[6] || '').split(',').map(&:strip).each { | color |
        unless color =~ color_regex then
            raise "invalid color code #{color}, must match #{color_regex}"
        end
    }
    labels_and_colors = labels.zip(colors).map { | label, color |
        [label, color || "%06X" % rand(16.pow(6))]
    }
    puts "Every pull request will be labeled with #{labels_and_colors}" 
    file_deliveries.each_delivery do | delivery |
        puts "Delivering #{delivery}"
        delivery_source_folder = "#{source_folder}/#{delivery.name}/."
        repo_slug = "#{delivery.owner}/#{delivery.repository}"
        clone_url = "https://#{github_user}:#{github_token}@#{github_server.split('://').last}/#{repo_slug}"
        censored_clone_url = clone_url.gsub(github_token, "<secret token>")
        destination = "#{workspace}/#{repo_slug}"
        unless clone_url.start_with?("https://#{github_user}") then
            raise "URL does not start with the expected preamble: #{censored_clone_url}"
        end
        puts "Cloning from #{censored_clone_url} to #{destination}"
        git = Git.clone(clone_url, destination)
        head_branch = "autodelivery_#{delivery.index}_from_#{origin_repo}@#{origin_sha}"
        if git.branches["origin/#{head_branch}"] then
            puts "Branch #{head_branch} already exists on origin: skipping delivery"
        else
            git.checkout(delivery.branch)
            git.branch(head_branch).checkout
            FileUtils.cp_r(delivery_source_folder, destination)
            git.add('.')
            if git.status.added.empty? && git.status.changed.empty? && git.status.deleted.empty? then
                puts 'No change w.r.t. the current status'
            else
                git.config('user.name', committer)
                git.config('user.email', email)
                message = "[Autodelivery] update #{delivery.name} from #{origin_repo}@#{origin_sha}"
                git.commit(message)
                git.push('origin', head_branch)
                # Create a pull request
                body = <<~PULL_REQUEST_BODY
                    This pull request has been created automatically by [Autodelivery](https://github.com/DanySK/autodelivery), at your service.
                    
                    To the best of this bot's understanding, it updates a content described as
                    
                    > #{delivery.name}
    
                    and this PR updates it to the same version of #{origin_repo}@#{origin_sha}.
                    
                    Hope it helps!
                PULL_REQUEST_BODY
                pull_request = client.create_pull_request(repo_slug, delivery.branch, head_branch, message, body)
                unless labels_and_colors.empty? then
                    repo_labels = client.labels(repo_slug).map(&:name)
                    labels_and_colors.each do | label, color |
                        unless repo_labels.include?(label) then
                            puts "Creating label #{label} with color #{color}"
                            client.add_label(repo_slug, label, color)
                        end
                    end
                    puts "Marking #{repo_slug}##{pull_request.number} with labels #{labels}"
                    client.add_labels_to_an_issue(repo_slug, pull_request.number, labels)
                end
            end
        end
        puts "Cleaning up #{destination}"
        FileUtils.rm_rf(Dir["#{destination}"])
    end
end

# Cleanup
puts 'Cleaning the workspace directory'
FileUtils.rm_rf(Dir["#{workspace}/*"])
puts 'Done'
