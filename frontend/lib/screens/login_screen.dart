import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:godigital_portal/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  int _selectedTab = 0; // 0 = Employee, 1 = Admin
  bool _rememberDevice = false;
  bool _obscurePassword = true;
  final bool _isLoading = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRememberedUser();
  }

  Future<void> _loadRememberedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberedUser = prefs.getString('remembered_login_user');
    final rememberedPassword = prefs.getString('remembered_login_password');

    if (!mounted) return;

    if (rememberedUser != null && rememberedUser.isNotEmpty) {
      setState(() {
        _emailController.text = rememberedUser;
        _passwordController.text = rememberedPassword ?? '';
        _rememberDevice = true;
      });
      debugPrint('📥 Remembered login loaded');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE0E0E0)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Screen height & width base panni responsive handle pannalam
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Container(
                          width: constraints.maxWidth >= 1000
                              ? 950
                              : double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 24,
                          ),
                          child: constraints.maxWidth >= 900
                              ? _buildDesktopLayout()
                              : _buildMobileLayout(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top navigation bar ──────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        children: [
          const Icon(
            Icons.grid_view_rounded,
            size: 26,
            color: Color(0xFF1A1A2E),
          ),
          const SizedBox(width: 8),
          const Text(
            'GoDigital Portal',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {},
            child: const Text(
              'Support',
              style: TextStyle(fontSize: 14, color: Color(0xFF555555)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Desktop layout (logo left, card right) ──────────────────────────────────

  Widget _buildDesktopLayout() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Center(child: _buildLogo(logoWidth: 280))),
        const SizedBox(width: 40),
        SizedBox(
          width: 400,
          child: _buildLoginCard(cardWidth: double.infinity),
        ),
      ],
    );
  }

  // ── Mobile / Tablet layout (logo top, card below) ───────────────────────────

  Widget _buildMobileLayout() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLogo(logoWidth: 180),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _buildLoginCard(cardWidth: double.infinity),
        ),
      ],
    );
  }

  // ── Logo ────────────────────────────────────────────────────────────────────

  Widget _buildLogo({required double logoWidth}) {
    return Image.asset(
      'assets/images/godigital_logo.png',
      width: logoWidth,
      fit: BoxFit.contain,
    );
  }

  // ── Login card ──────────────────────────────────────────────────────────────

  Widget _buildLoginCard({required double cardWidth}) {
    return Container(
      width: cardWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDDDDD)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabRow(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: _buildFormContent(),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
          _buildFooter(),
        ],
      ),
    );
  }

  // ── Tab switcher ────────────────────────────────────────────────────────────

  Widget _buildTabRow() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      child: Row(
        children: [_buildTab('Employee Login', 0), _buildTab('Admin Login', 1)],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF0F4FF) : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isSelected
                    ? const Color(0xFF2A52BE)
                    : const Color(0xFFDDDDDD),
                width: isSelected ? 2 : 1,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? const Color(0xFF1A3A8F)
                  : const Color(0xFF666666),
            ),
          ),
        ),
      ),
    );
  }

  // ── Form body ───────────────────────────────────────────────────────────────

  Widget _buildFormContent() {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                'Please enter your corporate credentials to continue.',
                style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            // Error message
            if (authService.error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  authService.error!,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
              ),

            // Email
            _fieldLabel('Email or Username'),
            const SizedBox(height: 8),
            _textField(
              controller: _emailController,
              hint: 'name@company.com',
              prefixIcon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              enabled: !authService.isLoading,
            ),
            const SizedBox(height: 18),

            // Password
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _fieldLabel('Password'),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF2A52BE),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _textField(
              controller: _passwordController,
              hint: '••••••••',
              prefixIcon: Icons.lock_outline,
              obscureText: _obscurePassword,
              enabled: !authService.isLoading,
              suffixIcon: GestureDetector(
                onTap: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                child: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: const Color(0xFFAAAAAA),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Remember device
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: _rememberDevice,
                    onChanged: authService.isLoading
                        ? null
                        : (v) => setState(() => _rememberDevice = v ?? false),
                    activeColor: const Color(0xFF2A52BE),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                    ),
                    side: const BorderSide(color: Color(0xFFCCCCCC)),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Remember this device',
                  style: TextStyle(fontSize: 13, color: Color(0xFF555555)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Sign In
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: authService.isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A3A8F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  elevation: 0,
                  disabledBackgroundColor: Colors.grey.shade400,
                ),
                child: authService.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          const Text(
            'New to the organization?  ',
            style: TextStyle(fontSize: 13, color: Color(0xFF777777)),
          ),
          GestureDetector(
            onTap: _handleCreateAccount,
            child: const Text(
              'Create an Admin Account',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A3A8F),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Color(0xFF333333),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    bool enabled = true,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      enabled: enabled,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
        prefixIcon: Icon(prefixIcon, size: 18, color: const Color(0xFFAAAAAA)),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF2A52BE), width: 1.5),
        ),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 12,
        ),
      ),
    );
  }

  // ── Login handler ───────────────────────────────────────────────────────────

  // Future<void> _handleLogin() async {
  //   final email = _emailController.text.trim();
  //   final password = _passwordController.text.trim();

  //   if (email.isEmpty || password.isEmpty) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('Please enter email and password.'),
  //         backgroundColor: Colors.redAccent,
  //       ),
  //     );
  //     return;
  //   }

  //   final authService = context.read<AuthService>();
  //   final isAdmin = _selectedTab == 1;

  //   final success = await authService.login(
  //     email,
  //     password,
  //     isAdmin,
  //     _rememberDevice,
  //   );

  //   if (!mounted) return;

  //   if (success) {
  //     final prefs = await SharedPreferences.getInstance();

  //     if (_rememberDevice) {
  //       await prefs.setString('remembered_login_user', email);
  //       await prefs.setString('remembered_login_password', password);
  //     } else {
  //       await prefs.remove('remembered_login_user');
  //       await prefs.remove('remembered_login_password');
  //     }

  //     _navigateBasedOnRole(authService.userRole, isAdmin);
  //     // _navigateToHome();
  //   }
  // }

  // void _navigateBasedOnRole(String? role, bool isAdmin) {
  //   if (isAdmin) {
  //     Navigator.pushReplacementNamed(context, '/admin');
  //     return;
  //   }

  //   final roleStr = role?.toLowerCase().trim() ?? '';
  //   String route = '/employee';

  //   if (roleStr.contains('ui') ||
  //       roleStr.contains('ux') ||
  //       roleStr.contains('graphic') ||
  //       roleStr.contains('designer') ||
  //       roleStr.contains('web')) {
  //     route = '/designer';
  //   } else if (roleStr.contains('video') || roleStr.contains('editor')) {
  //     route = '/videographer';
  //   } else if (roleStr.contains('ads')) {
  //     route = '/adsHandler';
  //   } else if (roleStr.contains('page')) {
  //     route = '/pageHandler';
  //   }

  //   Navigator.pushReplacementNamed(context, route);
  // }

  // void _navigateToHome() {
  //   debugPrint('➡️ Navigating to: /home');
  //   Navigator.pushReplacementNamed(context, '/home');
  // }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter email and password.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final authService = context.read<AuthService>();
    final isAdmin = _selectedTab == 1;

    var loginSucceeded = await authService.login(
      email,
      password,
      isAdmin,
      _rememberDevice,
    );

    if (!mounted) return;

    if (!loginSucceeded &&
        authService.errorCode == 'DEVICE_CHANGE_REASON_REQUIRED') {
      final reason = await _askDeviceChangeReason();
      if (reason == null || reason.isEmpty || !mounted) return;
      loginSucceeded = await authService.login(
        email,
        password,
        isAdmin,
        _rememberDevice,
        deviceChangeReason: reason,
      );
      if (!mounted || !loginSucceeded) return;
    }

    // Do not route based on an old in-memory session. The destination must be
    // reached only after this exact employee/admin login request succeeds.
    if (loginSucceeded) {
      final prefs = await SharedPreferences.getInstance();

      if (_rememberDevice) {
        await prefs.setString('remembered_login_user', email);
        await prefs.setString('remembered_login_password', password);
      } else {
        await prefs.remove('remembered_login_user');
        await prefs.remove('remembered_login_password');
      }

      if (!mounted) return;

      // Start a clean signed-in navigation stack.  This prevents an older
      // login route from appearing again when employees move between the
      // workspace and HRMS screens.
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/attendance',
        (route) => false,
      );
    }
  }

  Future<String?> _askDeviceChangeReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request device change'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Example: My registered phone is broken.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isNotEmpty) Navigator.pop(dialogContext, reason);
            },
            child: const Text('Send request'),
          ),
        ],
      ),
    );
  }

  void _handleCreateAccount() {
    debugPrint('Create Admin Account tapped');
  }
}

// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:godigital_portal/services/auth_service.dart';

// class LoginScreen extends StatefulWidget {
//   const LoginScreen({super.key});

//   @override
//   State<LoginScreen> createState() => _LoginScreenState();
// }

// class _LoginScreenState extends State<LoginScreen> {
//   int _selectedTab = 0; // 0 = Employee, 1 = Admin
//   bool _rememberDevice = false;
//   bool _obscurePassword = true;
//   final bool _isLoading = false;

//   final TextEditingController _emailController = TextEditingController();
//   final TextEditingController _passwordController = TextEditingController();

//   @override
//   void dispose() {
//     _emailController.dispose();
//     _passwordController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.white,
//       body: Column(
//         children: [
//           _buildTopBar(),
//           const Divider(height: 1, thickness: 1, color: Color(0xFFE0E0E0)),
//           Expanded(
//             child: LayoutBuilder(
//               builder: (context, constraints) {
//                 final isDesktop = constraints.maxWidth >= 900;
//                 return isDesktop
//                     ? _buildDesktopLayout()
//                     : _buildMobileLayout();
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // ── Top navigation bar ──────────────────────────────────────────────────────

//   Widget _buildTopBar() {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
//       child: Row(
//         children: [
//           const Icon(Icons.grid_view_rounded,
//               size: 26, color: Color(0xFF1A1A2E)),
//           const SizedBox(width: 8),
//           const Text(
//             'GoDigital Portal',
//             style: TextStyle(
//               fontSize: 17,
//               fontWeight: FontWeight.w600,
//               color: Color(0xFF1A1A2E),
//             ),
//           ),
//           const Spacer(),
//           TextButton(
//             onPressed: () {},
//             child: const Text(
//               'Support',
//               style: TextStyle(fontSize: 14, color: Color(0xFF555555)),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // ── Desktop layout (logo left, card right) ──────────────────────────────────

//   Widget _buildDesktopLayout() {
//     return Row(
//       children: [
//         Expanded(
//           child: Center(child: _buildLogo(logoWidth: 300)),
//         ),
//         Padding(
//           padding:
//               const EdgeInsets.symmetric(horizontal: 60.0, vertical: 40.0),
//           child: _buildLoginCard(cardWidth: 390),
//         ),
//       ],
//     );
//   }

//   // ── Mobile layout (logo top, card below, scrollable) ───────────────────────

//   Widget _buildMobileLayout() {
//     return SingleChildScrollView(
//       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
//       child: Column(
//         children: [
//           _buildLogo(logoWidth: 200),
//           const SizedBox(height: 32),
//           _buildLoginCard(cardWidth: double.infinity),
//         ],
//       ),
//     );
//   }

//   // ── Logo ────────────────────────────────────────────────────────────────────

//   Widget _buildLogo({required double logoWidth}) {
//     return Image.asset(
//       'assets/images/godigital_logo.png',
//       width: logoWidth,
//       fit: BoxFit.contain,
//       errorBuilder: (context, error, stackTrace) {
//         return Container(
//           width: logoWidth,
//           height: 200,
//           decoration: BoxDecoration(
//             color: Colors.blue[50],
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: const Icon(
//             Icons.business,
//             size: 80,
//             color: Colors.blue,
//           ),
//         );
//       },
//     );
//   }

//   // ── Login card ──────────────────────────────────────────────────────────────

//   Widget _buildLoginCard({required double cardWidth}) {
//     return Container(
//       width: cardWidth,
//       constraints: const BoxConstraints(maxWidth: 420),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(8),
//         border: Border.all(color: const Color(0xFFDDDDDD)),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: 0.06),
//             blurRadius: 14,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           _buildTabRow(),
//           Padding(
//             padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
//             child: _buildFormContent(),
//           ),
//           const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
//           _buildFooter(),
//         ],
//       ),
//     );
//   }

//   // ── Tab switcher ────────────────────────────────────────────────────────────

//   Widget _buildTabRow() {
//     return ClipRRect(
//       borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
//       child: Row(
//         children: [
//           _buildTab('Employee Login', 0),
//           _buildTab('Admin Login', 1),
//         ],
//       ),
//     );
//   }

//   Widget _buildTab(String label, int index) {
//     final isSelected = _selectedTab == index;
//     return Expanded(
//       child: GestureDetector(
//         onTap: () => setState(() => _selectedTab = index),
//         child: Container(
//           padding: const EdgeInsets.symmetric(vertical: 16),
//           decoration: BoxDecoration(
//             color: isSelected ? const Color(0xFFF0F4FF) : Colors.white,
//             border: Border(
//               bottom: BorderSide(
//                 color: isSelected
//                     ? const Color(0xFF2A52BE)
//                     : const Color(0xFFDDDDDD),
//                 width: isSelected ? 2 : 1,
//               ),
//             ),
//           ),
//           child: Text(
//             label,
//             textAlign: TextAlign.center,
//             style: TextStyle(
//               fontSize: 14,
//               fontWeight:
//                   isSelected ? FontWeight.w600 : FontWeight.w400,
//               color: isSelected
//                   ? const Color(0xFF1A3A8F)
//                   : const Color(0xFF666666),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   // ── Form body ───────────────────────────────────────────────────────────────

//   Widget _buildFormContent() {
//     return Consumer<AuthService>(
//       builder: (context, authService, _) {
//         return Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Center(
//               child: Text(
//                 'Welcome Back',
//                 style: TextStyle(
//                   fontSize: 24,
//                   fontWeight: FontWeight.w700,
//                   color: Color(0xFF1A1A2E),
//                 ),
//               ),
//             ),
//             const SizedBox(height: 6),
//             const Center(
//               child: Text(
//                 'Please enter your corporate credentials to continue.',
//                 style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
//                 textAlign: TextAlign.center,
//               ),
//             ),
//             const SizedBox(height: 24),

//             // Error message
//             if (authService.error != null)
//               Container(
//                 padding: const EdgeInsets.all(12),
//                 margin: const EdgeInsets.only(bottom: 16),
//                 decoration: BoxDecoration(
//                   color: Colors.red.shade50,
//                   border: Border.all(color: Colors.red.shade200),
//                   borderRadius: BorderRadius.circular(4),
//                 ),
//                 child: Text(
//                   authService.error!,
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: Colors.red.shade700,
//                   ),
//                 ),
//               ),

//             // Email
//             _fieldLabel('Email or Username'),
//             const SizedBox(height: 8),
//             _textField(
//               controller: _emailController,
//               hint: 'name@company.com',
//               prefixIcon: Icons.alternate_email,
//               keyboardType: TextInputType.emailAddress,
//               enabled: !authService.isLoading,
//             ),
//             const SizedBox(height: 18),

//             // Password
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 _fieldLabel('Password'),
//                 TextButton(
//                   onPressed: () {},
//                   style: TextButton.styleFrom(
//                     padding: EdgeInsets.zero,
//                     minimumSize: Size.zero,
//                     tapTargetSize: MaterialTapTargetSize.shrinkWrap,
//                   ),
//                   child: const Text(
//                     'Forgot Password?',
//                     style: TextStyle(
//                       fontSize: 13,
//                       fontWeight: FontWeight.w500,
//                       color: Color(0xFF2A52BE),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 8),
//             _textField(
//               controller: _passwordController,
//               hint: '••••••••',
//               prefixIcon: Icons.lock_outline,
//               obscureText: _obscurePassword,
//               enabled: !authService.isLoading,
//               suffixIcon: GestureDetector(
//                 onTap: () =>
//                     setState(() => _obscurePassword = !_obscurePassword),
//                 child: Icon(
//                   _obscurePassword ? Icons.visibility_off : Icons.visibility,
//                   size: 18,
//                   color: const Color(0xFFAAAAAA),
//                 ),
//               ),
//             ),
//             const SizedBox(height: 14),

//             // Remember device
//             Row(
//               children: [
//                 SizedBox(
//                   width: 18,
//                   height: 18,
//                   child: Checkbox(
//                     value: _rememberDevice,
//                     onChanged: authService.isLoading
//                         ? null
//                         : (v) =>
//                             setState(() => _rememberDevice = v ?? false),
//                     activeColor: const Color(0xFF2A52BE),
//                     shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(3)),
//                     side: const BorderSide(color: Color(0xFFCCCCCC)),
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 const Text(
//                   'Remember this device',
//                   style: TextStyle(fontSize: 13, color: Color(0xFF555555)),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 24),

//             // Sign In
//             SizedBox(
//               width: double.infinity,
//               height: 46,
//               child: ElevatedButton(
//                 onPressed: authService.isLoading ? null : _handleLogin,
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: const Color(0xFF1A3A8F),
//                   foregroundColor: Colors.white,
//                   shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(6)),
//                   elevation: 0,
//                   disabledBackgroundColor: Colors.grey.shade400,
//                 ),
//                 child: authService.isLoading
//                     ? const SizedBox(
//                         height: 20,
//                         width: 20,
//                         child: CircularProgressIndicator(
//                           valueColor:
//                               AlwaysStoppedAnimation<Color>(Colors.white),
//                           strokeWidth: 2,
//                         ),
//                       )
//                     : const Text(
//                         'Sign In',
//                         style: TextStyle(
//                             fontSize: 15,
//                             fontWeight: FontWeight.w600,
//                             letterSpacing: 0.5),
//                       ),
//               ),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   // ── Footer ──────────────────────────────────────────────────────────────────

//   Widget _buildFooter() {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
//       child: Wrap(
//         alignment: WrapAlignment.center,
//         children: [
//           const Text(
//             'New to the organization?  ',
//             style: TextStyle(fontSize: 13, color: Color(0xFF777777)),
//           ),
//           GestureDetector(
//             onTap: _handleCreateAccount,
//             child: const Text(
//               'Create an Admin Account',
//               style: TextStyle(
//                 fontSize: 13,
//                 fontWeight: FontWeight.w600,
//                 color: Color(0xFF1A3A8F),
//                 decoration: TextDecoration.underline,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // ── Helpers ─────────────────────────────────────────────────────────────────

//   Widget _fieldLabel(String text) {
//     return Text(
//       text,
//       style: const TextStyle(
//           fontSize: 13,
//           fontWeight: FontWeight.w500,
//           color: Color(0xFF333333)),
//     );
//   }

//   Widget _textField({
//     required TextEditingController controller,
//     required String hint,
//     required IconData prefixIcon,
//     TextInputType keyboardType = TextInputType.text,
//     bool obscureText = false,
//     bool enabled = true,
//     Widget? suffixIcon,
//   }) {
//     return TextField(
//       controller: controller,
//       obscureText: obscureText,
//       keyboardType: keyboardType,
//       enabled: enabled,
//       decoration: InputDecoration(
//         hintText: hint,
//         hintStyle:
//             const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
//         prefixIcon:
//             Icon(prefixIcon, size: 18, color: const Color(0xFFAAAAAA)),
//         suffixIcon: suffixIcon,
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(6),
//           borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
//         ),
//         enabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(6),
//           borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
//         ),
//         focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(6),
//           borderSide:
//               const BorderSide(color: Color(0xFF2A52BE), width: 1.5),
//         ),
//         filled: true,
//         fillColor: const Color(0xFFFAFAFA),
//         contentPadding:
//             const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
//       ),
//     );
//   }

//   // ── Login handler ───────────────────────────────────────────────────────────

//   Future<void> _handleLogin() async {
//     final email = _emailController.text.trim();
//     final password = _passwordController.text.trim();

//     if (email.isEmpty || password.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Please enter email and password.'),
//           backgroundColor: Colors.redAccent,
//         ),
//       );
//       return;
//     }

//     final authService = context.read<AuthService>();
//     final isAdmin = _selectedTab == 1;

//     debugPrint('🔐 Login attempt: $email (admin: $isAdmin)');

//     final success = await authService.login(email, password, isAdmin);

//     if (!mounted) return;

//     if (success) {
//       debugPrint('✅ Login successful! Role: ${authService.userRole}');
//       // Navigate to HomeScreen for all users after login
//       _navigateToHome();
//     } else {
//       debugPrint('❌ Login failed: ${authService.error}');
//     }
//   }

//   // ── Navigate to Home Screen ─────────────────────────────────────────────────

//   /// Navigate to HomeScreen after successful login
//   /// The HomeScreen will handle post-login initialization
//   void _navigateToHome() {
//     debugPrint('➡️ Navigating to: /home');
//     Navigator.pushReplacementNamed(context, '/home');
//   }

//   void _handleCreateAccount() {
//     debugPrint('Create Admin Account tapped');
//   }
// }
