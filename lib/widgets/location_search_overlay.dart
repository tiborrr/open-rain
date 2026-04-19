import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/location_service.dart';
import '../utils/result.dart';
import '../view_models/home_view_model.dart';

/// Search overlay reading the shared [HomeViewModel] from the surrounding
/// `Provider`.
///
/// Wraps `viewModel.searchCities` (a `Command1`) so progress and error state
/// come from the command itself instead of being re-implemented locally.
class LocationSearchOverlay extends StatefulWidget {
  const LocationSearchOverlay({super.key});

  @override
  State<LocationSearchOverlay> createState() => _LocationSearchOverlayState();
}

class _LocationSearchOverlayState extends State<LocationSearchOverlay> {
  final TextEditingController _searchController = TextEditingController();

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      context.read<HomeViewModel>().searchCities.clearResult();
      return;
    }
    await context.read<HomeViewModel>().searchCities.execute(query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              ListenableBuilder(
                listenable: viewModel.searchCities,
                builder: (context, _) {
                  if (viewModel.searchCities.running) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: viewModel.searchCities,
                  builder: (context, _) {
                    final result = viewModel.searchCities.result;
                    final results = switch (result) {
                      Ok<List<LocationResult>>(value: final v) => v,
                      _ => const <LocationResult>[],
                    };
                    return ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final result = results[index];
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
