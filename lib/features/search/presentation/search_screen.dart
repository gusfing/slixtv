import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/config/app_config.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Channel;
import '../../movies/domain/models.dart' show VodItem;
import '../../series/domain/models.dart' show SeriesItem;

class SearchScreen extends ConsumerStatefulWidget {
  final void Function(Channel)? onChannelTap;
  final void Function(VodItem)? onMovieTap;
  final void Function(SeriesItem)? onSeriesTap;
  const SearchScreen({super.key, this.onChannelTap, this.onMovieTap, this.onSeriesTap});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(AppConfig.searchDebounce, () {
      ref.read(searchQueryProvider.notifier).state = q;
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: TextField(
          controller: _ctrl, onChanged: _onChanged, autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: AppStrings.searchHint, border: InputBorder.none, hintStyle: TextStyle(color: AppColors.textTertiary)),
        ),
        actions: [if (_ctrl.text.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: () { _ctrl.clear(); ref.read(searchQueryProvider.notifier).state = ''; })],
      ),
      body: query.trim().length < 2
          ? Center(child: Icon(Icons.search_rounded, size: 80, color: AppColors.textHint.withValues(alpha: 0.3)))
          : results.when(
              loading: () => const LoadingIndicator(message: 'Searching...'),
              error: (e, _) => ErrorDisplay(message: 'Search failed'),
              data: (r) {
                final ch = r['channels'] ?? [];
                final mv = r['movies'] ?? [];
                final sr = r['series'] ?? [];
                if (ch.isEmpty && mv.isEmpty && sr.isEmpty) return Center(child: Text(AppStrings.noResults, style: TextStyle(color: AppColors.textTertiary)));
                return ListView(children: [
                  if (ch.isNotEmpty) ...[const SectionHeader(title: 'Channels'), ...ch.cast<Channel>().map((c) => ChannelTile(name: c.name, logo: c.logo, onTap: () => widget.onChannelTap?.call(c)))],
                  if (mv.isNotEmpty) ...[const SectionHeader(title: 'Movies'), SizedBox(height: AppDimensions.posterHeight + 40, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md), itemCount: mv.length, separatorBuilder: (context, index) => const SizedBox(width: AppDimensions.sm), itemBuilder: (_, i) { final m = mv[i] as VodItem; return PosterCard(title: m.name, imageUrl: m.poster, subtitle: m.year, onTap: () => widget.onMovieTap?.call(m)); }))],
                  if (sr.isNotEmpty) ...[const SectionHeader(title: 'Series'), SizedBox(height: AppDimensions.posterHeight + 40, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md), itemCount: sr.length, separatorBuilder: (context, index) => const SizedBox(width: AppDimensions.sm), itemBuilder: (_, i) { final s = sr[i] as SeriesItem; return PosterCard(title: s.name, imageUrl: s.poster, subtitle: s.year, onTap: () => widget.onSeriesTap?.call(s)); }))],
                  const SizedBox(height: 100),
                ]);
              },
            ),
    );
  }
}
