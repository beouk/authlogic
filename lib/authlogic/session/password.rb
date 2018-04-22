module Authlogic
  module Session
    # Handles authenticating via a traditional username and password.
    module Password
      def self.included(klass)
        klass.class_eval do
          extend Config
          include InstanceMethods
          validate :validate_by_password, if: :authenticating_with_password?

          class << self
            attr_accessor :configured_password_methods
          end
        end
      end

      # Password configuration
      module Config
        # Authlogic tries to validate the credentials passed to it. One part of
        # validation is actually finding the user and making sure it exists.
        # What method it uses the do this is up to you.
        #
        # Let's say you have a UserSession that is authenticating a User. By
        # default UserSession will call User.find_by_login(login). You can
        # change what method UserSession calls by specifying it here. Then in
        # your User model you can make that method do anything you want, giving
        # you complete control of how users are found by the UserSession.
        #
        # Let's take an example: You want to allow users to login by username or
        # email. Set this to the name of the class method that does this in the
        # User model. Let's call it "find_by_username_or_email"
        #
        #   class User < ActiveRecord::Base
        #     def self.find_by_username_or_email(login)
        #       find_by_username(login) || find_by_email(login)
        #     end
        #   end
        #
        # Now just specify the name of this method for this configuration option
        # and you are all set. You can do anything you want here. Maybe you
        # allow users to have multiple logins and you want to search a has_many
        # relationship, etc. The sky is the limit.
        #
        # * <tt>Default:</tt> "find_by_smart_case_login_field"
        # * <tt>Accepts:</tt> Symbol or String
        def find_by_login_method(value = nil)
          rw_config(:find_by_login_method, value, "find_by_smart_case_login_field")
        end
        alias_method :find_by_login_method=, :find_by_login_method

        # The text used to identify credentials (username/password) combination
        # when a bad login attempt occurs. When you show error messages for a
        # bad login, it's considered good security practice to hide which field
        # the user has entered incorrectly (the login field or the password
        # field). For a full explanation, see
        # http://www.gnucitizen.org/blog/username-enumeration-vulnerabilities/
        #
        # Example of use:
        #
        #   class UserSession < Authlogic::Session::Base
        #     generalize_credentials_error_messages true
        #   end
        #
        #   This would make the error message for bad logins and bad passwords
        #   look identical:
        #
        #   Login/Password combination is not valid
        #
        #   Alternatively you may use a custom message:
        #
        #   class UserSession < AuthLogic::Session::Base
        #     generalize_credentials_error_messages "Your login information is invalid"
        #   end
        #
        #   This will instead show your custom error message when the UserSession is invalid.
        #
        # The downside to enabling this is that is can be too vague for a user
        # that has a hard time remembering their username and password
        # combinations. It also disables the ability to to highlight the field
        # with the error when you use form_for.
        #
        # If you are developing an app where security is an extreme priority
        # (such as a financial application), then you should enable this.
        # Otherwise, leaving this off is fine.
        #
        # * <tt>Default</tt> false
        # * <tt>Accepts:</tt> Boolean
        def generalize_credentials_error_messages(value = nil)
          rw_config(:generalize_credentials_error_messages, value, false)
        end
        alias_method :generalize_credentials_error_messages=, :generalize_credentials_error_messages

        # The name of the method you want Authlogic to create for storing the
        # login / username. Keep in mind this is just for your
        # Authlogic::Session, if you want it can be something completely
        # different than the field in your model. So if you wanted people to
        # login with a field called "login" and then find users by email this is
        # completely doable. See the find_by_login_method configuration option
        # for more details.
        #
        # * <tt>Default:</tt> klass.login_field || klass.email_field
        # * <tt>Accepts:</tt> Symbol or String
        def login_field(value = nil)
          rw_config(:login_field, value, klass.login_field || klass.email_field)
        end
        alias_method :login_field=, :login_field

        # Works exactly like login_field, but for the password instead. Returns
        # :password if a login_field exists.
        #
        # * <tt>Default:</tt> :password
        # * <tt>Accepts:</tt> Symbol or String
        def password_field(value = nil)
          rw_config(:password_field, value, login_field && :password)
        end
        alias_method :password_field=, :password_field

        # The name of the method in your model used to verify the password. This
        # should be an instance method. It should also be prepared to accept a
        # raw password and a crytped password.
        #
        # * <tt>Default:</tt> "valid_password?" defined in acts_as_authentic/password.rb
        # * <tt>Accepts:</tt> Symbol or String
        def verify_password_method(value = nil)
          rw_config(:verify_password_method, value, "valid_password?")
        end
        alias_method :verify_password_method=, :verify_password_method
      end

      # Password related instance methods
      module InstanceMethods
        def initialize(*args)
          unless self.class.configured_password_methods
            configure_password_methods
            self.class.configured_password_methods = true
          end
          super
        end

        # Returns the login_field / password_field credentials combination in
        # hash form.
        def credentials
          if authenticating_with_password?
            details = {}
            details[login_field.to_sym] = send(login_field)
            details[password_field.to_sym] = "<protected>"
            details
          else
            super
          end
        end

        # Accepts the login_field / password_field credentials combination in
        # hash form.
        #
        # You must pass an actual Hash, `ActionController::Parameters` is
        # specifically not allowed.
        #
        # See `Authlogic::Session::Foundation#credentials=` for an overview of
        # all method signatures.
        def credentials=(value)
          super
          values = Array.wrap(value)
          if values.first.is_a?(Hash)
            sliced = values
              .first
              .with_indifferent_access
              .slice(login_field, password_field)
            sliced.each do |field, val|
              next if val.blank?
              send("#{field}=", val)
            end
          end
        end

        def invalid_password?
          invalid_password == true
        end

        private

          def add_invalid_password_error
            if generalize_credentials_error_messages?
              add_general_credentials_error
            else
              errors.add(
                password_field,
                I18n.t("error_messages.password_invalid", default: "is not valid")
              )
            end
          end

          def add_login_not_found_error
            if generalize_credentials_error_messages?
              add_general_credentials_error
            else
              errors.add(
                login_field,
                I18n.t("error_messages.login_not_found", default: "is not valid")
              )
            end
          end

          def authenticating_with_password?
            login_field && (!send(login_field).nil? || !send("protected_#{password_field}").nil?)
          end

          def configure_password_methods
            define_login_field_methods
            define_password_field_methods
          end

          def define_login_field_methods
            return unless login_field
            self.class.send(:attr_writer, login_field) unless respond_to?("#{login_field}=")
            self.class.send(:attr_reader, login_field) unless respond_to?(login_field)
          end

          def define_password_field_methods
            return unless password_field
            self.class.send(:attr_writer, password_field) unless respond_to?("#{password_field}=")
            self.class.send(:define_method, password_field) {} unless respond_to?(password_field)

            # The password should not be accessible publicly. This way forms
            # using form_for don't fill the password with the attempted
            # password. To prevent this we just create this method that is
            # private.
            self.class.class_eval <<-EOS, __FILE__, __LINE__ + 1
              private
                def protected_#{password_field}
                  @#{password_field}
                end
            EOS
          end

          # In keeping with the metaphor of ActiveRecord, verification of the
          # password is referred to as a "validation".
          def validate_by_password
            self.invalid_password = false
            validate_by_password__blank_fields
            return if errors.count > 0
            self.attempted_record = search_for_record(find_by_login_method, send(login_field))
            if attempted_record.blank?
              add_login_not_found_error
              return
            end
            validate_by_password__invalid_password
          end

          def validate_by_password__blank_fields
            if send(login_field).blank?
              errors.add(
                login_field,
                I18n.t("error_messages.login_blank", default: "cannot be blank")
              )
            end
            if send("protected_#{password_field}").blank?
              errors.add(
                password_field,
                I18n.t("error_messages.password_blank", default: "cannot be blank")
              )
            end
          end

          # Verify the password, usually using `valid_password?` in
          # `acts_as_authentic/password.rb`. If it cannot be verified, we
          # refer to it as "invalid".
          def validate_by_password__invalid_password
            unless attempted_record.send(
              verify_password_method,
              send("protected_#{password_field}")
            )
              self.invalid_password = true
              add_invalid_password_error
            end
          end

          attr_accessor :invalid_password

          def find_by_login_method
            self.class.find_by_login_method
          end

          def login_field
            self.class.login_field
          end

          def add_general_credentials_error
            error_message =
              if self.class.generalize_credentials_error_messages.is_a? String
                self.class.generalize_credentials_error_messages
              else
                "#{login_field.to_s.humanize}/Password combination is not valid"
              end
            errors.add(
              :base,
              I18n.t("error_messages.general_credentials_error", default: error_message)
            )
          end

          def generalize_credentials_error_messages?
            self.class.generalize_credentials_error_messages
          end

          def password_field
            self.class.password_field
          end

          def verify_password_method
            self.class.verify_password_method
          end
      end
    end
  end
end
