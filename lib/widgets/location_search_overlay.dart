import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/home_view_model.dart';
import '../services/location_service.dart';

class LocationSearchOverlay extends StatefulWidget {
  const LocationSearchOverlay({super.key});

  @override
  State<LocationSearchOverlay> createState() => _LocationSearchOverlayState();
}

class _LocationSearchOverlayState extends State<LocationSearchOverlay> {
  final TextEditingController _searchController = TextEditingController();
  List<LocationResult> _results = [];
  bool _isSearching = false;

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _isSearching = true);
    final results = await context.read<HomeViewModel>().searchCities(query);
    if (mounted) {
      setState(() {
        _results = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      ),
      child: BackdropFilter(
        filter: ColorFilter.mode(
          Colors.black.withValues(alpha: 0.1),
          BlendMode.darken,
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search for city...',
                border: InputBorder.none,
              ),
              onChanged: _performSearch,
            ),
          ),
          body: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.my_location),
                title: const Text('Use Current Location'),
                onTap: () {
                  viewModel.resetToGps();
                  Navigator.pop(context);
                },
              ),
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    return ListTile(
                      leading: const Icon(Icons.location_city),
                      title: Text(result.name),
                      onTap: () {
                        viewModel.setManualLocation(
                          result.latitude,
                          result.longitude,
                          result.name,
                        );
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
