# -*- encoding : utf-8 -*-
class Channels::BaseController < ApplicationController
    before_filter :force_http
    
    private
    
    def force_http
        redirect_to(protocol: 'http', host:"#{request.subdomain}.#{::Configuration[:base_domain]}")
    end
end
