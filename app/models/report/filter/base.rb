module Report::Filter
  class Base < Report::Chainable
    Report::Operator.load

    inherited_attribute   :available_operators,
                            :list => true, :map => :to_operator,
                            :uniq => true
    inherited_attribute   :default_operator, :map => :to_operator

    accepts_property :values, :value, :operator

    mattr_accessor :skip_inherited_operators
    self.skip_inherited_operators = [:time_operators, "y", "n"]

    attr_accessor :values

    ##
    # A Filter is 'heavy' if it possibly returns a _hughe_ number of available_values.
    # In that case the UI-guys should think twice about displaying all the values.
    def self.heavy?
      false
    end

    def value=(val)
      self.values = [val]
    end

    def self.use(*names)
      operators = []
      names.each do |name|
        dont_inherit :available_operators if skip_inherited_operators.include? name
        case name
        when String, Report::Operator then operators << name.to_operator
        when Symbol then operators.push(*Report::Operator.send(name))
        else fail "dunno what to do with #{name.inspect}"
        end
      end
      available_operators *operators
    end

    use :default_operators

    def self.new(*args, &block) # :nodoc:
      # this class is abstract. instances are only allowed from child classes
      raise "#{self.name} is an abstract class" if base?
      super
    end

    def self.inherited(klass)
      if base?
        self.dont_display!
        klass.display!
      end
      super
    end

    def self.available_values(user)
      raise NotImplementedError, "subclass responsibility"
    end

    def correct_position?
      child.nil? or child.filter?
    end

    def from_for(scope)
      super + self.class.table_joins
    end

    def filter?
      true
    end

    def valid?
      @operator ? @operator.validate(values) : true
    end

    def errors
      @operator ? @operator.errors : []
    end

    def group_by_fields
      []
    end

    def initialze(child = nil, options = {})
      raise ArgumentError, "Child has to be a Filter." if child and not child.filter?
      @values = []
      super
    end

    def might_be_responsible
      parent
    end

    def operator
      (@operator || self.class.default_operator || Report::Operator.default_operator).to_operator
    end

    def operator=(value)
      @operator = value.to_operator.tap do |o|
        raise ArgumentError, "#{o.inspect} not supported by #{inspect}." unless available_operators.include? o
      end
    end

    def responsible_for_sql?
      top?
    end

    def to_hash
      raise NotImplementedError
    end

    def sql_statement
      super.tap do |query|
        arity   = operator.arity
        values  = [*self.values].compact
        values  = values[0, arity] if values and arity >= 0 and arity != values.size
        operator.modify(query, field, *values) unless field.empty?
      end
    end
  end
end