import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Channel, Category;
import '../../player/presentation/player_screen.dart';
import '../../../core/widgets/parental_pin_dialog.dart';

class RadioScreen extends ConsumerStatefulWidget {
  const RadioScreen({super.key});

  @override
  ConsumerState<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends ConsumerState<RadioScreen> {
  String? _selectedCategoryId;
  String _selectedCategoryName = '';
  final List<Channel> _channels = [];
  bool _isLoading = false;
  String? _error;

  void _fetchChannels() async {
    if (_selectedCategoryId == null) return;

    setState(() {
      _isLoading = true;
      _channels.clear();
      _error = null;
    });

    try {
      final authState = ref.read(authProvider);
      List<Channel> newChannels;
      if (authState.authType == 'xtream') {
        newChannels = await ref.read(xtreamApiProvider).getLiveStreams(categoryId: _selectedCategoryId);
      } else {
        newChannels = await ref.read(stalkerApiProvider).getChannels(categoryId: _selectedCategoryId);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _channels.addAll(newChannels);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load radio stations: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    }
  }

  Future<void> _playRadio(Channel channel) async {
    final lockState = ref.read(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      final authenticated = await ParentalPinDialog.show(context);
      if (!authenticated) return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
    try {
      final stalkerApi = ref.read(stalkerApiProvider);
      final streamUrl = await stalkerApi.createLink(channel.cmd, 'itv');
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: streamUrl,
          title: channel.name,
          contentId: 'ch_${channel.id}',
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load station: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(radioCategoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0C0F),
        title: const Text('Radio', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (err, _) => Center(child: Text('Error loading radio categories', style: TextStyle(color: AppColors.error))),
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(child: Text('No radio categories found.', style: TextStyle(color: Colors.white54)));
          }
          if (_selectedCategoryId == null) {
            _selectedCategoryId = categories.first.id;
            _selectedCategoryName = categories.first.title;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fetchChannels();
            });
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              return isMobile ? _buildMobileView(categories) : _buildTabletView(categories);
            },
          );
        },
      ),
    );
  }

  Widget _buildMobileView(List<Category> categories) {
    return Column(
      children: [
        Container(
          height: 60,
          decoration: const BoxDecoration(
            color: Color(0xFF0C0C0F),
            border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = _selectedCategoryId == cat.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(cat.title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70)),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: const Color(0xFF1A1A1E),
                  side: BorderSide.none,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedCategoryId = cat.id;
                        _selectedCategoryName = cat.title;
                      });
                      _fetchChannels();
                    }
                  },
                ),
              );
            },
          ),
        ),
        Expanded(child: _buildGrid()),
      ],
    );
  }

  Widget _buildTabletView(List<Category> categories) {
    return Row(
      children: [
        Container(
          width: 220,
          decoration: const BoxDecoration(
            color: Color(0xFF0C0C0F),
            border: Border(right: BorderSide(color: Colors.white10, width: 0.5)),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = _selectedCategoryId == cat.id;
              return ListTile(
                title: Text(cat.title, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                selected: isSelected,
                selectedTileColor: AppColors.primary.withOpacity(0.1),
                onTap: () {
                  setState(() {
                    _selectedCategoryId = cat.id;
                    _selectedCategoryName = cat.title;
                  });
                  _fetchChannels();
                },
              );
            },
          ),
        ),
        Expanded(child: _buildGrid()),
      ],
    );
  }

  Widget _buildGrid() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchChannels, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_channels.isEmpty) {
      return const Center(child: Text('No stations found', style: TextStyle(color: Colors.white30)));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemCount: _channels.length,
      itemBuilder: (context, index) {
        final channel = _channels[index];
        return GestureDetector(
          onTap: () => _playRadio(channel),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (channel.logo.isNotEmpty)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: CachedNetworkImage(
                        imageUrl: channel.logo,
                        httpHeaders: ApiClient().getStalkerHeaders(),
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => const Icon(Icons.radio, color: Colors.white24, size: 40),
                      ),
                    ),
                  )
                else
                  const Expanded(child: Icon(Icons.radio, color: Colors.white24, size: 40)),
                Container(
                  padding: const EdgeInsets.all(8),
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF15151A),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Text(
                    channel.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
