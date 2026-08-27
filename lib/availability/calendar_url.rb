# frozen_string_literal: true

module Availability
  # Normalizes calendar subscription schemes into URLs Net::HTTP can fetch.
  module CalendarUrl
    module_function

    def normalize(value)
      value.sub(/\Awebcal:/i, 'https:')
    end
  end
end
