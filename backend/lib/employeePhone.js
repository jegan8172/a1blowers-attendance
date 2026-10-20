function normalizePhone(value) {
  if (value == null || value === '') return null;
  if (typeof value !== 'string') throw new Error('Phone number must be text');
  const phone = value.trim();
  if (!phone) return null;
  if (phone.length > 32 || !/^[0-9+(). -]+$/.test(phone) || !/[0-9]/.test(phone)) {
    throw new Error('Enter a valid phone number using up to 32 characters');
  }
  return phone;
}
module.exports = { normalizePhone };
