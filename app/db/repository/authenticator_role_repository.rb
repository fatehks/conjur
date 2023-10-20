# frozen_string_literal: true

module DB
  module Repository
    # This class is responsible for loading the variables associated with a
    # particular type of authenticator. Each authenticator requires a Data
    # Object and Data Object Contract (for validation). Data Objects that
    # fail validation are not returned.
    #
    # This class includes one public methods:
    #   - `find` - returns a single authenticator based on the provided type,
    #     account, and service identifier.
    #
    class AuthenticatorRoleRepository
      def initialize(authenticator:, role_contract: nil, role: Role, logger: Rails.logger)
        @authenticator = authenticator
        @role = role
        @logger = logger
        @role_contract = role_contract
      end

      def find(role_identifier:)
        role = @role[role_identifier.identifier]
        unless role.present?
          raise(Errors::Authentication::Security::RoleNotFound, role_identifier.role_for_error)
        end

        return role unless role.resource?

        relevant_annotations = relevant_annotations(
          annotations: {}.tap { |h| role.resource.annotations.each {|a| h[a.name] = a.value }}
        )

        validate_role_annotations_against_contract(
          annotations: relevant_annotations
        )

        annotations_match?(
          role_annotations: relevant_annotations,
          target_annotations: role_identifier.annotations
        )

        role
      end

      private

      def validate_role_annotations_against_contract(annotations:)
        # If authenticator requires annotations, verify some are present
        if @authenticator.annotations_required && annotations.empty?
          raise(Errors::Authentication::Constraints::RoleMissingAnyRestrictions)
        end

        # Only run contract validations if they are present
        return if @role_contract.nil?

        annotations.each do |annotation, value|
          annotation_valid = @role_contract.new(authenticator: @authenticator, utils: ::Util::ContractUtils).call(
            annotation: annotation,
            annotation_value: value,
            annotations: annotations
          )
          next if annotation_valid.success?

          raise(annotation_valid.errors.first.meta[:exception])
        end
      end

      # Need to account for the following two options:
      # Annotations relevant to specific authenticator
      # - !host
      #   id: myapp
      #   annotations:
      #     authn-jwt/raw/ref: valid

      # Annotations relevant to type of authenticator
      # - !host
      #   id: myapp
      #   annotations:
      #     authn-jwt/project_id: myproject
      #     authn-jwt/aud: myaud

      def relevant_annotations(annotations:)
        # Verify that at least one service specific auth token is present
        if annotations.keys.any?{|k,_|k.include?(@authenticator.type.to_s) } &&
            !annotations.keys.any?{|k,_|k.include?("#{@authenticator.type}/#{@authenticator.service_id}") }
          raise(Errors::Authentication::Constraints::RoleMissingAnyRestrictions)
        end

        generic = annotations
          .select{|k, _| k.count('/') == 1 }
          .select{|k, _| k.match?(%r{^authn-jwt/})}
          .reject{|k, _| k.match?(%r{^authn-jwt/#{@authenticator.service_id}})}
          .transform_keys{|k| k.split('/').last}

        specific = annotations
          .select{|k, _| k.count('/') > 1 }
          .select{|k, _| k.match?(%r{^authn-jwt/#{@authenticator.service_id}/})}
          .transform_keys{|k| k.split('/').last}

        generic.merge(specific)
      end

      def annotations_match?(role_annotations:, target_annotations:)
        # If there are no annotations to match, just return
        return if target_annotations.empty?

        role_annotations.each do |annotation, value|
          next unless annotation.present?

          @logger.debug(LogMessages::Authentication::ResourceRestrictions::ValidatingResourceRestrictionOnRequest.new(annotation))
          if target_annotations.key?(annotation) && target_annotations[annotation] == value
            @logger.debug(LogMessages::Authentication::ResourceRestrictions::ValidatedResourceRestrictionsValues.new(annotation))
            next
          end

          unless target_annotations.key?(annotation)
            raise(Errors::Authentication::AuthnJwt::JwtTokenClaimIsMissing, annotation)
          end

          raise(Errors::Authentication::ResourceRestrictions::InvalidResourceRestrictions, annotation)
        end

        @logger.debug(LogMessages::Authentication::ResourceRestrictions::ValidatedResourceRestrictions.new)
        @logger.debug(LogMessages::Authentication::AuthnJwt::ValidateRestrictionsPassed.new)
      end
    end
  end
end
