// ═══════════════════════════════════════════════════════════════════════════════
// FIXED: Client Dropdown - Client Names Properly Visible
// File: lib/widgets/client_dropdown.dart
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/api_config.dart';


class ClientDropdown extends StatefulWidget {
  final Function(String clientId, String clientName) onClientSelected;
  final String? initialClientId;

  const ClientDropdown({
    super.key,
    required this.onClientSelected,
    this.initialClientId,
  });

  @override
  State<ClientDropdown> createState() => _ClientDropdownState();
}

class _ClientDropdownState extends State<ClientDropdown> {
  TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> clients = [];
  List<Map<String, dynamic>> filteredClients = [];
  
  bool isLoading = true;
  String? selectedClientId;
  String? selectedClientName;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // ✅ Load all clients from backend
  Future<void> _loadClients() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/clients/list'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        setState(() {
          clients = List<Map<String, dynamic>>.from(data['data']);
          filteredClients = clients;
          isLoading = false;
        });

        debugPrint('✅ Loaded ${clients.length} clients');
      } else {
        throw Exception('Failed to load clients');
      }
    } catch (error) {
      setState(() => isLoading = false);
      debugPrint('❌ Error loading clients: $error');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading clients: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ Search clients
  void _searchClients(String query) {
    if (query.isEmpty) {
      setState(() => filteredClients = clients);
      return;
    }

    final searchQuery = query.toLowerCase();
    setState(() {
      filteredClients = clients
          .where((client) {
            final name = (client['company_name'] ?? '').toLowerCase();
            return name.contains(searchQuery);
          })
          .toList();
    });

    debugPrint('Search: "$query" found ${filteredClients.length} clients');
  }

  // ✅ Handle client selection
  void _onClientSelected(String clientId, String clientName) {
    setState(() {
      selectedClientId = clientId;
      selectedClientName = clientName;
      searchController.text = clientName;
    });

    // Call parent callback
    widget.onClientSelected(clientId, clientName);

    debugPrint('✅ Selected: $clientName (ID: $clientId)');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        const Text(
          'Client Name *',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),

        // Search/Dropdown Field
        if (isLoading)
          Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: selectedClientId != null ? Colors.green : Colors.grey,
                width: selectedClientId != null ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: searchController,
              onChanged: _searchClients,
              decoration: InputDecoration(
                hintText: 'Select or search client',
                prefixIcon: const Icon(Icons.business),
                suffixIcon: selectedClientId != null
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onTap: () {
                // Show dropdown when tapping
                FocusScope.of(context).requestFocus(FocusNode());
              },
            ),
          ),

        const SizedBox(height: 8),

        // Client list dropdown
        if (!isLoading && filteredClients.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 250),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: filteredClients.length,
              itemBuilder: (context, index) {
                final client = filteredClients[index];
                final clientId = client['id'].toString();
                final clientName = client['company_name'] ?? 'Unknown';
                final isSelected = selectedClientId == clientId;

                return Container(
                  color: isSelected ? Colors.blue.shade50 : Colors.transparent,
                  child: ListTile(
                    title: Text(
                      clientName,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.blue : Colors.black,
                      ),
                    ),
                    leading: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () {
                      _onClientSelected(clientId, clientName);
                    },
                    dense: true,
                  ),
                );
              },
            ),
          )
        else if (!isLoading && searchController.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'No clients found',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),

        const SizedBox(height: 8),

        // Selected client info
        if (selectedClientName != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              border: Border.all(color: Colors.green),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Selected: $selectedClientName',
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}