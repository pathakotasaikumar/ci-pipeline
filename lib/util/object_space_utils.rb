class ObjectSpaceUtils
  def self.load_pipeline_classes(parent_class:)
    result = []
    classes = load_classes(parent_class: parent_class)

    classes.each do |klass|
      class_name = klass.to_s

      if !class_name.include?("Pipeline::")
        next
      end

      # log services aren't awailable here yet
      # this APIs are meant to be called by ServiceContainer itself
      # normally, no other APIs should use this class
      puts "  - pipeline container, loading class: #{class_name}"

      result << klass
    end

    result
  end

  def self.load_classes(parent_class:)
    result = []

    # passing Class instead of bare ObjectSpace.each_object() call gives
    #  ~ 0.15 sec performance
    #  load only needed classed without other objects
    ObjectSpace.each_object(Class) do |klass|
      next unless Module === klass

      begin
        class_name = klass.to_s

        if class_name.include?("#")
          next
        end

        result << klass if parent_class >= klass
      rescue NameError => e
        # this is to prevent troubled classed from.to_s failures
        # shoud not affect pipeline classes
        # NameError: undefined local variable or method `num' for #<Socksify::Color:0x00000003d41388>
        # https://bamboo.qcpaws.qantas.com.au/browse/AMS01-C031S01CI331-6
      end
    end

    result
  end
end
