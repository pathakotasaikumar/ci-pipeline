module Qantas
  module Pipeline
    module Core
      # Provides access to application container info
      # Wraps Defaults.sections with class props in downcase
      class AppContainerInfo
        attr_reader :ams
        attr_reader :qda
        attr_reader :as
        attr_reader :ase
        attr_reader :ase_number
        attr_reader :plan_key
        attr_reader :branch
        attr_reader :build
        attr_reader :env
        attr_reader :asbp_type

        def initialize(sections:)
          @sections = sections

          @ams        = _fetch_value(sections, :ams)
          @qda        = _fetch_value(sections, :qda)
          @as         = _fetch_value(sections, :as)
          @ase        = _fetch_value(sections, :ase)

          @ase_number = _fetch_value(sections, :ase_number)
          @plan_key   = _fetch_value(sections, :plan_key)

          @branch     = _fetch_value(sections, :branch)
          @build      = _fetch_value(sections, :build)

          @env        = _fetch_value(sections, :env)
          @asbp_type  = _fetch_value(sections, :asbp_type)
        end

        def to_s
          [
            @ams,
            @qda,
            @as,
            @ase,
            @ase_number,
            @plan_key,
            @branch,
            @build,
            @env,
            @asbp_type
          ].join("-")
        end

        def ==(other_object)
          if other_object.nil?
            return false
          end

          if !other_object.is_a?(AppContainerInfo)
            return false
          end

          return hashed_value == other_object.hashed_value
        end

        def hashed_value
          [
            @ams,
            @qda,
            @as,
            @ase,
            @ase_number,
            @plan_key,
            @branch,
            @build,
            @env,
            @asbp_type
          ].join("-")
        end

        private

        def _fetch_value(section, name)
          section.fetch(name).downcase
        end
      end
    end
  end
end
