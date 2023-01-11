module ActiveGraph
  module Migrations
    module Schema
      class << self
        def fetch_schema_data
          { constraints: fetch_constraint_descriptions.sort, indexes: fetch_index_descriptions.sort }
        end

        def synchronize_schema_data(schema_data, remove_missing)
          queries = []
          ActiveGraph::Base.read_transaction do
            queries += drop_and_create_queries(fetch_constraint_descriptions, schema_data[:constraints], remove_missing)
            queries += drop_and_create_queries(fetch_index_descriptions, schema_data[:indexes], remove_missing)
          end
          ActiveGraph::Base.write_transaction do
            queries.each(&ActiveGraph::Base.method(:query))
          end
        end

        private

        def fetch_constraint_descriptions
          ActiveGraph::Base.query('CALL db.constraints() YIELD description').map(&:first)
        end

        def fetch_index_descriptions
          result = ActiveGraph::Base.raw_indexes
          result.reject do |row|
            byebug
            if row.keys.include?(:description)
              # v3 indexes
              row[:type] == 'node_unique_property'
            else
              # v4 indexes
              row[:uniqueness] == 'UNIQUE'
            end
          end.map do |row|
            if row.keys.include?(:description)
              row[:description]
            else
              row.try(:description)
            end
          end
        end

        # The code below does not seem to work as intended
        # def fetch_index_descriptions
        #   ActiveGraph::Base.raw_indexes do |keys, result|
        #     if keys.include?(:description)
        #       v3_indexes(result)
        #     else
        #       v4_indexes(result)
        #     end
        #   end
        # end

        # def v3_indexes(result)
        #   result.reject do |row|
        #     # These indexes are created automagically when the corresponding constraints are created
        #     row[:type] == 'node_unique_property'
        #   end.map { |row| row[:description] }
        # end

        # def v4_indexes(result)
        #   result.reject do |row|
        #     # These indexes are created automagically when the corresponding constraints are created
        #     row[:uniqueness] == 'UNIQUE'
        #   end.map(&method(:description))
        # end

        def description(row)
          "INDEX FOR (n:#{row[:labelsOrTypes].first}) ON (#{row[:properties].map { |prop| "n.#{prop}" }.join(', ')})"
        end

        def drop_and_create_queries(existing, specified, remove_missing)
          [].tap do |queries|
            if remove_missing
              (existing - specified).each { |description| queries << "DROP #{description}" }
            end

            (specified - existing).each { |description| queries << "CREATE #{description}" }
          end
        end
      end
    end
  end
end
