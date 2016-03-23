module ActiveFedora::Associations::Builder
  class Association #:nodoc:
    class << self
      attr_accessor :extensions
    end
    self.extensions = []

    VALID_OPTIONS = [:class_name, :predicate, :type_validator].freeze

    # configure_dependency
    def self.build(model, name, options, &block)
      if model.dangerous_attribute_method?(name)
        Deprecation.warn(ActiveFedora::Base, "You tried to define an association named #{name} on the model #{model.name}, but " \
                             "this will conflict with a method #{name} already defined by ActiveFedora. " \
                             "Please choose a different association name.")
      end

      extension = define_extensions model, name, &block
      reflection = create_reflection model, name, nil, options, extension
      define_accessors(model, reflection)
      define_callbacks(model, reflection)
      define_validations model, reflection
      reflection
    end

    def self.create_reflection(model, name, scope, options, extension = nil)
      unless name.is_a?(Symbol)
        name = name.to_sym
        Deprecation.warn(ActiveFedora::Base, "association names must be a Symbol")
      end
      validate_options(options)
      translate_property_to_predicate(options)

      scope = build_scope(scope, extension)
      name = better_name(name)

      ActiveFedora::Reflection.create(macro, name, scope, options, model)
    end

    def self.build_scope(scope, extension)
      new_scope = scope

      new_scope = proc { instance_exec(&scope) } if scope && scope.arity == 0

      new_scope = wrap_scope new_scope, extension if extension

      new_scope
    end

    def self.wrap_scope(scope, _extension)
      scope
    end

    def self.macro
      raise NotImplementedError
    end

    def self.valid_options(_options)
      VALID_OPTIONS + Association.extensions.flat_map(&:valid_options)
    end

    def self.validate_options(options)
      options.assert_valid_keys(valid_options(options))
    end

    def self.better_name(name)
      name
    end

    def self.translate_property_to_predicate(options)
      return unless options[:property]
      Deprecation.warn Association, "the :property option to `#{model}.#{macro} :#{name}' is deprecated and will be removed in active-fedora 10.0. Use :predicate instead", caller(5)
      options[:predicate] = predicate(options.delete(:property))
    end

    # Returns the RDF predicate as defined by the :property attribute
    def self.predicate(property)
      return property if property.is_a? RDF::URI
      ActiveFedora::Predicates.find_graph_predicate(property)
    end

    def self.define_extensions(_model, _name)
    end

    def self.define_callbacks(model, reflection)
      if dependent = reflection.options[:dependent]
        check_dependent_options(dependent)
        add_destroy_callbacks(model, reflection)
      end

      Association.extensions.each do |extension|
        extension.build model, reflection
      end
    end

    # Defines the setter and getter methods for the association
    # class Post < ActiveRecord::Base
    #   has_many :comments
    # end
    #
    # Post.first.comments and Post.first.comments= methods are defined by this method...
    def self.define_accessors(model, reflection)
      mixin = model.generated_association_methods
      name = reflection.name
      define_readers(mixin, name)
      define_writers(mixin, name)
    end

    def self.define_readers(mixin, name)
      mixin.class_eval <<-CODE, __FILE__, __LINE__ + 1
        def #{name}(*args)
          association(:#{name}).reader(*args)
        end
      CODE
    end

    def self.define_writers(mixin, name)
      mixin.class_eval <<-CODE, __FILE__, __LINE__ + 1
        def #{name}=(value)
          association(:#{name}).writer(value)
        end
      CODE
    end

    def self.define_validations(_model, _reflection)
      # noop
    end

    def self.add_destroy_callbacks(model, reflection)
      name = reflection.name
      model.before_destroy lambda do |o|
        a = o.association(name)
        a.handle_dependency if a.respond_to? :handle_dependency
      end
    end

    def self.valid_dependent_options
      raise NotImplementedError
    end

    def self.check_dependent_options(dependent)
      unless valid_dependent_options.include? dependent
        raise ArgumentError, "The :dependent option must be one of #{valid_dependent_options}, but is :#{dependent}"
      end
    end
  end
end
