/// Resolves the correct branding logo asset path for a given role.
///
/// Admin and employee/user asset groups are kept in separate folders
/// (assets/branding/admin, assets/branding/user) so the two never mix.
/// Callers must pass the role explicitly — there is no default — so the
/// path can never silently fall back to the wrong role's assets.
String brandingLogoAssetForRole({required bool isAdmin}) {
  return isAdmin
      ? 'assets/branding/admin/client_logo.png'
      : 'assets/branding/user/client_logo.png';
}
