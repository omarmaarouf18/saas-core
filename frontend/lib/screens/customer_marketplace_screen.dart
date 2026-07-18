import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../models/marketplace_service.dart';
import '../core/constants.dart';
import 'job_status_screen.dart';

class CustomerMarketplaceScreen extends StatefulWidget {
  const CustomerMarketplaceScreen({super.key});

  @override
  State<CustomerMarketplaceScreen> createState() =>
      _CustomerMarketplaceScreenState();
}

class _CustomerMarketplaceScreenState extends State<CustomerMarketplaceScreen> {
  final _latController =
      TextEditingController(text: "30.0444"); // default Cairo lat
  final _lonController =
      TextEditingController(text: "31.2357"); // default Cairo lon
  final _radiusController = TextEditingController(text: "50"); // default radius

  String _selectedCategory =
      'all'; // 'all', 'delivery', 'transport', 'shipping'
  String _sortBy = 'price'; // 'price' or 'none'
  bool _nearBy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadServices();
    });
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void _loadServices() {
    final lat = double.tryParse(_latController.text.trim()) ?? 30.0444;
    final lon = double.tryParse(_lonController.text.trim()) ?? 31.2357;
    final radius = double.tryParse(_radiusController.text.trim()) ?? 50.0;

    Provider.of<MarketplaceProvider>(context, listen: false).fetchServices(
      nearBy: _nearBy,
      lat: lat,
      lon: lon,
      radius: radius,
      sortBy: _sortBy,
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'delivery':
        return Icons.delivery_dining;
      case 'transport':
        return Icons.directions_car;
      case 'shipping':
        return Icons.local_shipping;
      default:
        return Icons.business;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final marketplace = Provider.of<MarketplaceProvider>(context);

    // Filter services client-side by category if not 'all'
    final filteredServices = _selectedCategory == 'all'
        ? marketplace.services
        : marketplace.services
            .where((s) => s.category == _selectedCategory)
            .toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Marketplace"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () async {
              await auth.logout();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter & Coordinates Control Panel
          Card(
            margin: const EdgeInsets.all(12),
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Location Coordinates row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latController,
                          decoration: const InputDecoration(
                            labelText: "Latitude",
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _lonController,
                          decoration: const InputDecoration(
                            labelText: "Longitude",
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _radiusController,
                          decoration: const InputDecoration(
                            labelText: "Radius (KM)",
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Filters row
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: "Category",
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: 'all', child: Text("All Categories")),
                            ...serviceCategoryLabels.entries.map(
                              (entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedCategory = val;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _sortBy,
                          decoration: const InputDecoration(
                            labelText: "Sort By",
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'price', child: Text("Price")),
                            DropdownMenuItem(
                                value: 'none', child: Text("None")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _sortBy = val;
                              });
                              _loadServices();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _loadServices,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 16),
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                        ),
                        child: const Icon(Icons.search, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Services Listing
          Expanded(
            child: marketplace.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredServices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              "No services found nearby.",
                              style: TextStyle(
                                  fontSize: 16, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: filteredServices.length,
                        itemBuilder: (context, index) {
                          final service = filteredServices[index];
                          final categoryLabel =
                              serviceCategoryLabels[service.category] ??
                                  service.category;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .secondary
                                        .withOpacity(0.2),
                                    foregroundColor:
                                        Theme.of(context).colorScheme.primary,
                                    child: Icon(
                                        _getCategoryIcon(service.category)),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          service.name,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                categoryLabel,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              "${service.distanceKM} km away",
                                              style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 13),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          "Base: \$${service.tenantBasePrice} + \$${service.tenantPricePerKM}/km",
                                          style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 13),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "Est. Price: \$${service.finalPrice}",
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .secondary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () => _showBookingDialog(
                                        context, service, auth.token!),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      foregroundColor: Theme.of(context)
                                          .colorScheme
                                          .onSecondary,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                    child: const Text("Book"),
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
    );
  }

  void _showBookingDialog(
      BuildContext context, MarketplaceService service, String userToken) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return _BookingDialog(
          service: service,
          userToken: userToken,
          customerLat: double.tryParse(_latController.text.trim()) ?? 30.0444,
          customerLon: double.tryParse(_lonController.text.trim()) ?? 31.2357,
        );
      },
    );
  }
}

class _BookingDialog extends StatefulWidget {
  final MarketplaceService service;
  final String userToken;
  final double customerLat;
  final double customerLon;

  const _BookingDialog({
    required this.service,
    required this.userToken,
    required this.customerLat,
    required this.customerLon,
  });

  @override
  State<_BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<_BookingDialog> {
  bool _isSubmitting = false;

  Future<void> _confirmBooking() async {
    setState(() {
      _isSubmitting = true;
    });

    final provider = Provider.of<MarketplaceProvider>(context, listen: false);
    try {
      final job = await provider.bookJob(
        serviceId: widget.service.id,
        userId: widget.userToken,
        latitude: widget.customerLat,
        longitude: widget.customerLon,
        paymentMethod: "cod", // forced COD only
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // close dialog

      if (job != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => JobStatusScreen(job: job),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Booking Failed: $e"),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryLabel = serviceCategoryLabels[widget.service.category] ??
        widget.service.category;
    return AlertDialog(
      title: const Text("Confirm Booking"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.service.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text("Category: $categoryLabel",
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Pickup Distance:"),
                Text("${widget.service.distanceKM} km"),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Estimated Total:"),
                Text(
                  "\$${widget.service.finalPrice}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              "Payment Method",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Forced Option: Cash on Delivery (COD)
            RadioListTile<String>(
              value: "cod",
              groupValue: "cod",
              onChanged: null, // disabled to force selection
              title: const Text("Cash on Delivery (COD)"),
              subtitle:
                  const Text("Pay in cash directly to the driver upon arrival"),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            // Inline note explaining escrow/other methods are deferred
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "Note: Escrow payments and wallet deductions are currently deferred for this beta launch.",
                style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _confirmBooking,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text("Confirm & Request"),
        ),
      ],
    );
  }
}
