module Multimethod

  class Signature
    include Comparable

    attr_accessor :mod     # The Module the signature is bound to.
    attr_accessor :class_method # True if the signature is bound to the class.
    attr_accessor :name    # The name of the method signature.
    attr_accessor :parameter # The parameters of the method, self included.

    attr_accessor :min_args
    attr_accessor :max_args
    attr_accessor :restarg
    attr_accessor :default

    attr_accessor :multimethod
    attr_accessor :method
    attr_accessor :file
    attr_accessor :line

    attr_accessor :verbose

    def initialize(*opts)
      opts = Hash[*opts]

      @mod = opts[:mod]
      @name = opts[:name]
      @class_method = false
      @parameter = [ ]
      @min_args = 0
      @max_args = 0
      @restarg = nil
      @default = nil

      @method = nil
      @multimethod = nil

      @verbose = nil

      @score = { }

      # Handle a string representation of a signature.
      case params = opts[:string]
      when String
        scan_string(params)
      end

      # Handle other parameters.
      case params = opts[:parameter]
      when Array
        scan_parameters(params)
      when String
        scan_parameters_string(params)
      end
    end
    

    # For sort
    def <=>(x)
      @parameter <=> x.parameter
    end


    def mod
      if @mod && @mod.kind_of?(String)
        @mod = Table.instance.name_to_object(@mod, 
                                              nil, 
                                              @method && @method.file, 
                                              @method && @method.line)
      end

      @mod
    end


    # Scan
    def scan_string(str, need_names = true)

      str.sub!(/\A\s+/, '')

      if md = /\A(\w+(::\w+)*)#(\w+)/.match(str)
        str = md.post_match
        @mod = md[1] unless @mod
        @name = md[3]
      elsif md = /\A(\w+(::\w+)*)\.(\w+)/.match(str)
        str = md.post_match
        @mod = md[1] unless @mod
        @class_method = true
        @name = md[3]
      elsif md  = /\A((\w+(::\w+)*)\s+)?def\s+(self\.)?(\w+)/.match(str)
        str = md.post_match
        @mod = md[2] unless @mod
        @class_method = ! ! md[4]
        @name = md[5]
      else
        raise NameError, "Syntax error in multimethod signature at #{str.inspect}"
      end

      # Resolve mod name.
      # FIXME!

      # Add self parameter.
      add_self

      # Parse parameter list.
      if md = /\A\(/.match(str)
        str = md.post_match

        str = scan_parameters_string(str, need_names)

        $stderr.puts "  str=#{str.inspect}" if @verbose

        if md = /\A\)/.match(str)
          str = md.post_match
        else
          raise NameError, "Syntax error in multimethod parameters at #{str.inspect}"
        end
      end
      
      str
    end


    def scan_parameters_string(str, need_names = true)

      # Add self parameter at front.
      add_self

      $stderr.puts "scan_parameters_string(#{str.inspect})" if @verbose

      until str.empty?
        name = nil
        type = nil
        default = nil
        
        str.sub!(/\A\s+/, '')

        $stderr.puts "  str=#{str.inspect}" if @verbose
        
        if md = /\A(\w+(::\w+)*)\s+(\w+)/s.match(str)
          # $stderr.puts "   pre_match=#{md.pre_match.inspect}"
          # $stderr.puts "   md[0]=#{md[0].inspect}"
          str = md.post_match
          type = md[1]
          name = md[3]
        elsif md = /\A(\*?\w+)/s.match(str)
          # $stderr.puts "   pre_match=#{md.pre_match.inspect}"
          # $stderr.puts "   md[0]=#{md[0].inspect}"
          str = md.post_match
          type = nil
          name = md[1]
        else
          raise NameError, "Syntax error in multimethod parameters: expected type and/or name at #{str.inspect}"
        end
        
        $stderr.puts "  type=#{type.inspect}" if @verbose       
        $stderr.puts "  name=#{name.inspect}" if @verbose       

        # Parse parameter default.
        if md = /\A\s*=\s*/.match(str)
          str = md.post_match

          in_paren = 0
          default = ''
          until str.empty?
            # $stderr.puts "    default: str=#{str.inspect}"
            # $stderr.puts "    default: params=#{parameter_to_s}"

            if md = /\A(\s+)/s.match(str)
              str = md.post_match
              default = default + md[1]
            end

            if md = /\A("([^"\\]|\\.)*")/s.match(str)
              str = md.post_match
              default = default + md[1]
            elsif md = /\A('([^'\\]|\\.)*')/s.match(str)
              str = md.post_match
              default = default + md[1]
            elsif md = /\A(\()/.match(str)
              str = md.post_match
              in_paren = in_paren + 1
              default = default + md[1]
            elsif in_paren > 0 && md = /\A(\))/s.match(str)
              str = md.post_match
              in_paren = in_paren - 1
              default = default + md[1]
            elsif in_paren == 0 && md = /\A,/s.match(str)
              break
            elsif md = /\A(\w+)/s.match(str)
              str = md.post_match
              default = default + md[1]
            elsif md = /\A(.)/s.match(str)
              str = md.post_match
              default = default + md[1] 
            end
          end
        end

        # Add parameter
        p = Parameter.new(name, type, default)
        add_parameter(p)
        $stderr.puts "  params=#{parameter_to_s}" if @verbose       

        # Parse , or )
        str.sub!(/\A\s+/, '')
        if ! str.empty? 
          if md = /\A,/s.match(str)
            str = md.post_match
          elsif md = /\A\)/s.match(str)
            $stderr.puts "  DONE: #{to_s}\n  Remaining: #{str.inspect}" if @verbose
            break
          else
            raise NameError, "Syntax error in multimethod parameters: expected ',' or ')' at #{str.inspect}"
          end
        end
 
      end

      $stderr.puts "scan_parameters_string(...): DONE: #{to_s}\n  Remaining: #{str}" if @verbose

      str
    end


    def scan_parameters(params)
      # Add self parameter at front.
      add_self

      until params.empty?
        name = nil
        type = nil
        restarg = false
        default = nil
        
        if x = params.shift
          case x
          when Class
            type = x
          else
            name = x
          end
        end

        if ! name && (x = params.shift)
          name = x
        end

        raise("Parameter name expected, found #{name.inspect}") unless name.kind_of?(String) || name.kind_of?(Symbol)
        raise("Parameter type expected, found #{type.inspect}") unless type.kind_of?(Module) || type.nil?

        p = Parameter.new(name, type, default)
        add_parameter(p)
      end

    end
    

    # Add self parameter at front.
    def add_self
      add_parameter(Parameter.new('self', mod)) if @parameter.empty?
    end


    def add_parameter(p)
      if p.restarg
        raise("Too many restargs") if @restarg
        @restarg = p
        @max_args = nil
      end
      if p.default
        (@default ||= [ ]).push(p)
      end

      p.i = @parameter.size
      @parameter.push(p)
      p.signature = self

      unless p.default || p.restarg
        @min_args = @parameter.size
      end

      unless @restarg
        @max_args = @parameter.size
      end
    end


    def score_cached(args)
      unless x = @score[args]
        x = @score[args] =
          score(args)
      end
      x
    end


    def score(args)
      
      if @min_args > args.size
        # Not enough args
        score = nil
      elsif @max_args && @max_args < args.size
        # Too many args?
        # $stderr.puts "max_args = #{@max_args}, args.size = #{args.size}"
        score = nil
      else
        # Interpret how close the argument type is to the parameter's type.
        i = -1
        score = args.collect{|a| parameter_at(i = i + 1).score(a)}

        # Handle score for trailing restargs.
        if @restarg || @default
          while (i = i + 1) < @parameter.size
            # $stderr.puts "  Adding score i=#{i}"
            score << parameter_at(i).score(NilClass)
          end
        end

        # If any argument cannot match, avoid this method.
        score = nil if score.index(nil)
      end

      # if true || @name =~ /_bar$/
      #   $stderr.puts "    Method: score #{self.to_s} #{args.inspect} => #{score.inspect}"
      # end

      score
    end
    

    def parameter_at(i)
      if i >= @parameter.size && @restarg
        @restarg
      else
        @parameter[i]
      end
    end

 
    def to_s(name = nil)
      name ||= @name || '_'
      p = @parameter.clone
      rcvr = p.shift
      "#{rcvr.type.name}##{name}(#{parameter_to_s(p)})"
    end


    def parameter_to_s(p = nil)
      p ||= @parameter
      p.collect{|x| x.to_s}.join(', ')
    end


    def to_ruby_def(name = nil)
      name ||= @name || '_'
      "def #{name}(#{to_ruby_arg})"
    end


    def to_ruby_signature(name = nil)
      name ||= @name || '_'
      p = @parameter.clone
      rcvr = p.shift
      m = mod
      "#{m && m.name}##{name}(#{to_ruby_arg})"
    end


    def to_ruby_arg
      x = @parameter.clone
      x.shift
      x.collect{|x| x.to_ruby_arg}.join(', ')
    end


    def inspect
      to_s
    end

  end # class
end # module

