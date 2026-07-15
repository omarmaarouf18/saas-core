import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../core/constants.dart';

class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key});

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadServices();
    });
  }

  Future<void> _loadServices() async {
    await Provider.of<OwnerProvider>(context, listen: false).fetchServices();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final owner = Provider.of<OwnerProvider>(context);
    final user = auth.user;

    if (user == null) {
      return const Center(child: Text("Unauthenticated"));
    }

    final isKycApproved = user.kycStatus == "approved";
    // Filter services belonging to this tenant/owner
    final myServices = owner.services.where((s) => s['tenant_id'] == user.id).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Configure Services"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadServices,
        child: owner.isLoading && myServices.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (!isKycApproved)
                    Container(
                      color: Colors.amber.shade100,
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "KYC Approval Pending: You cannot publish new services until your profile is approved by an administrator.",
                              style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: myServices.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 100),
                              Center(
                                child: Text(
                                  "No services configured yet.\nTap the + button to create a service.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: myServices.length,
                            itemBuilder: (context, index) {
                              final svc = myServices[index];
                              final categoryLabel = serviceCategoryLabels[svc['category']] ?? svc['category'];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            svc['name'] ?? '',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Chip(
                                            label: Text(categoryLabel),
                                            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                            labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                                          ),
                                        ],
                                      ),
                                      const Divider(),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "Base Price: \$${(svc['tenant_base_price'] as num?)?.toStringAsFixed(2) ?? '0.00'}",
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                          Text(
                                            "Rate per KM: \$${(svc['tenant_price_per_km'] as num?)?.toStringAsFixed(2) ?? '0.00'}",
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "Coordinates: (${(svc['latitude'] as num?)?.toStringAsFixed(4) ?? '0.0000'}, ${(svc['longitude'] as num?)?.toStringAsFixed(4) ?? '0.0000'})",
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isKycApproved ? () => _showCreateServiceDialog(context, user.id) : null,
        backgroundColor: isKycApproved ? Theme.of(context).colorScheme.secondary : Colors.grey,
        foregroundColor: isKycApproved ? Theme.of(context).colorScheme.onSecondary : Colors.white,
        tooltip: isKycApproved ? "Add Service" : "KYC Pending",
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateServiceDialog(BuildContext context, String ownerId) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final basePriceController = TextEditingController();
    final pricePerKMController = TextEditingController();
    final latController = TextEditingController(text: "30.0444"); // Cairo default
    final lonController = TextEditingController(text: "31.2357");

    String selectedCategory = 'delivery';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Create New Service"),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: "Service Name"),
                        validator: (value) => value == null || value.trim().isEmpty ? "Name is required" : null,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(labelText: "Category"),
                        items: serviceCategoryLabels.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedCategory = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: basePriceController,
                        decoration: const InputDecoration(labelText: "Base Price (\$)"),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) return "Base price is required";
                          final val = double.tryParse(value);
                          if (val == null || val < 0) return "Invalid price";
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: pricePerKMController,
                        decoration: const InputDecoration(labelText: "Rate per KM (\$)"),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) return "Rate is required";
                          final val = double.tryParse(value);
                          if (val == null || val < 0) return "Invalid rate";
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: latController,
                        decoration: const InputDecoration(labelText: "Latitude"),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) return "Required";
                          final val = double.tryParse(value);
                          if (val == null || val < -90.0 || val > 90.0) return "Must be between -90 and 90";
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: lonController,
                        decoration: const InputDecoration(labelText: "Longitude"),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) return "Required";
                          final val = double.tryParse(value);
                          if (val == null || val < -180.0 || val > 180.0) return "Must be between -180 and 180";
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final provider = Provider.of<OwnerProvider>(context, listen: false);
                      try {
                        await provider.createService(
                          name: nameController.text.trim(),
                          category: selectedCategory,
                          tenantBasePrice: double.parse(basePriceController.text),
                          tenantPricePerKM: double.parse(pricePerKMController.text),
                          latitude: double.parse(latController.text),
                          longitude: double.parse(lonController.text),
                          ownerId: ownerId,
                        );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Service created successfully!")),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Failed to create service: $e")),
                          );
                        }
                      }
                    }
                  },
                  child: const Text("Create"),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
