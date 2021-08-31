require 'values'

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
            if delivery.kind_of?(Array)
                delivery_name = delivery.first
                owners = delivery.last || {}
                while owners.kind_of?(Array) && !owners.empty? do
                    if owners.first.kind_of?(Hash) then
                        owners = owners.inject({}) { | a, b | a.merge(b) { |key, left, right| left.merge(right) } }
                    elsif owner.first.kind_of?(Array) then
                        owners = owners.flatten
                    end
                end
                if owners.kind_of?(Hash)
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
                else
                    raise "Expected an owners descriptor (Hash) but got: #{delivery}"
                end
            else
                raise "Expected a delivery (2-ple) but got: #{delivery}"
            end
        end
    end
end
