# frozen_string_literal: true

require "securerandom"
require "date"

# Simplified VCard models for demo purposes
module VCardDemo
  # Birthday property for vCard
  class VcardBday
    attr_accessor :value

    def initialize(value:)
      @value = value
    end

    def to_s
      value.to_s
    end

    def to_h
      { value: value }
    end
  end

  # Telephone property for vCard
  class VcardTel
    attr_accessor :value, :type, :pref

    def initialize(value:, type: nil, pref: nil)
      @value = value
      @type = type
      @pref = pref
    end

    def to_s
      "#{value} (#{type})"
    end

    def to_h
      { value: value, type: type, pref: pref }
    end
  end

  # Structured name for vCard
  class VcardName
    attr_accessor :family, :given, :additional, :prefix, :suffix

    def initialize(family: nil, given: nil, additional: nil, prefix: nil, suffix: nil)
      @family = family
      @given = given
      @additional = additional
      @prefix = prefix
      @suffix = suffix
    end

    def full_name
      parts = [prefix, given, additional, family, suffix].compact.reject(&:empty?)
      parts.join(" ")
    end

    def to_s
      full_name
    end

    def to_h
      {
        family: family,
        given: given,
        additional: additional,
        prefix: prefix,
        suffix: suffix
      }
    end
  end

  # Main vCard class
  class Vcard
    attr_accessor :version, :fn, :n, :tel, :email, :org, :bday, :uid

    def initialize(version: "4.0", fn: nil, n: nil, tel: [], email: [], org: nil, bday: nil, uid: nil)
      @version = version
      @fn = fn
      @n = n
      @tel = tel || []
      @email = email || []
      @org = org
      @bday = bday
      @uid = uid || SecureRandom.uuid
    end

    def primary_email
      email&.first
    end

    def primary_phone
      tel&.first
    end

    def age
      return nil unless bday&.value

      birth_date = parse_birth_date
      return nil unless birth_date

      today = Date.today
      age = today.year - birth_date.year
      age -= 1 if today < birth_date.next_year(age)
      age
    end

    def to_s
      "#{fn} (#{primary_email})"
    end

    def to_h
      {
        version: version,
        fn: fn,
        n: n&.to_h,
        tel: tel.map(&:to_h),
        email: email,
        org: org,
        bday: bday&.to_h,
        uid: uid
      }
    end

    private

    def parse_birth_date
      return nil unless bday&.value

      Date.parse(bday.value.to_s) rescue nil
    end
  end
end
