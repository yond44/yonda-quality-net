# frozen_string_literal: true

module Api
  module V1
    class AuthenticationController < ApiController
      skip_before_action :require_tenant!

      # POST /api/v1/auth/login
      def authenticate
        user = User.find_by(email: params[:email].to_s.downcase)

        return json_error('Invalid email or password', :unauthorized) unless user&.authenticate(params[:password])

        return json_error('Invalid email or password', :unauthorized) unless user.role == 'admin'

        # The tenant comes only from the user's own organization — never from a
        # client-supplied header and never from "the first organization" (audit F1).
        organization = user.organization
        return json_error('Account is not assigned to an organization', :unauthorized) unless organization

        token = JsonWebToken.encode({ user_id: user.id, role: user.role, scheme: organization.scheme })

        json_response({ token:, user: { id: user.id, email: user.email, role: user.role } })
      end
    end
  end
end
