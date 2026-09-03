# Matches BSON ObjectId hex rules without depending on bson.cr.
# Walk bytes: size 24, each byte 0-9 / a-f / A-F. No regex. No extra allocation.
Alumna::Formats.register("object_id", "must be a valid ObjectId") do |v|
  next false unless v.bytesize == 24
  valid = true
  v.each_byte do |b|
    # Same ranges as BSON::ObjectId.validate.
    unless (0x30_u8 <= b <= 0x39_u8) || # '0'-'9'
           (0x61_u8 <= b <= 0x66_u8) || # 'a'-'f'
           (0x41_u8 <= b <= 0x46_u8)    # 'A'-'F'
      valid = false
      break
    end
  end
  valid
end
