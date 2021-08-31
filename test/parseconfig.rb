require_relative '../hash_deliveries'
require 'yaml'

Dir['../**/test/**.*ml'].filter { |file| file =~ /.+ya?ml/ }.each do | file |
    content = YAML.load_file(file)
    puts(content)
    for keyword in ['secrets', 'files'] do
        section = content[keyword] || {}
        section.each_delivery do | delivery, index |
            puts "Delivery #{delivery} with index #{index}"
        end
    end
end
