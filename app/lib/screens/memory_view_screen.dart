import 'package:flutter/material.dart';
import '../data/area_network.dart';
import '../memories/memory.dart';
import '../memories/memory_repository.dart';
import 'memories_screen.dart';

String memoryDate(BuildContext context, WalkMemory memory) =>
    MaterialLocalizations.of(
      context,
    ).formatMediumDate(memory.createdAt.toLocal());

class MemoryPhoto extends StatelessWidget {
  const MemoryPhoto({super.key, required this.memory, this.fit = BoxFit.cover});
  final WalkMemory memory;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => memory.photo == null
      ? const Center(child: Icon(Icons.photo_outlined, size: 40))
      : HeroMode(
          enabled: !MediaQuery.disableAnimationsOf(context),
          child: Hero(
            tag: 'memory-photo-${memory.id}',
            child: Image.memory(
              memory.photo!,
              fit: fit,
              cacheWidth: 1200,
              errorBuilder: (_, _, _) =>
                  const Center(child: Text('Photo cannot be displayed')),
            ),
          ),
        );
}

class MemoryCard extends StatefulWidget {
  const MemoryCard({
    super.key,
    required this.memory,
    required this.store,
    required this.onTap,
  });
  final WalkMemory memory;
  final MemoryRepository store;
  final VoidCallback onTap;
  @override
  State<MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends State<MemoryCard> {
  late Future<WalkMemory?> photo = _load();
  Future<WalkMemory?> _load() => widget.memory.hasPhoto
      ? widget.store.read(widget.memory.id, widget.memory.draft)
      : Future.value(widget.memory);
  @override
  void didUpdateWidget(covariant MemoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memory != widget.memory || oldWidget.store != widget.store) {
      photo = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.memory;
    final colors = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
        ),
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 16),
        child: InkWell(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (m.hasPhoto)
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: FutureBuilder<WalkMemory?>(
                    future: photo,
                    builder: (context, snapshot) => snapshot.hasError
                        ? const Center(
                            child: Text('Open memory to retry photo'),
                          )
                        : MemoryPhoto(memory: snapshot.data ?? m),
                  ),
                )
              else
                Container(
                  height: 72,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colors.secondaryContainer,
                        colors.surfaceContainerLow,
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.format_quote_rounded,
                    size: 38,
                    color: colors.onSecondaryContainer,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(memoryDate(context, m)),
                        if (m.draft) const Text('Draft · Continue'),
                        if (m.hasLocation)
                          const Icon(Icons.place_outlined, size: 18),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MemoryViewScreen extends StatefulWidget {
  const MemoryViewScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.store,
    this.networks = const [],
  });
  final List<WalkMemory> items;
  final int initialIndex;
  final MemoryRepository store;
  final List<AreaNetwork> networks;
  @override
  State<MemoryViewScreen> createState() => _MemoryViewScreenState();
}

class _MemoryViewScreenState extends State<MemoryViewScreen> {
  late final controller = PageController(initialPage: widget.initialIndex);
  late int index = widget.initialIndex;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${index + 1} of ${widget.items.length}'),
      actions: [
        IconButton(
          tooltip: 'Edit memory',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MemoryEditor(
                  store: widget.store,
                  memory: widget.items[index],
                  networks: widget.networks,
                ),
              ),
            );
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    ),
    body: PageView.builder(
      controller: controller,
      itemCount: widget.items.length,
      onPageChanged: (value) => setState(() => index = value),
      itemBuilder: (context, i) => _MemoryPage(
        key: ValueKey(widget.items[i].id),
        memory: widget.items[i],
        store: widget.store,
      ),
    ),
  );
}

class _MemoryPage extends StatefulWidget {
  const _MemoryPage({super.key, required this.memory, required this.store});
  final WalkMemory memory;
  final MemoryRepository store;
  @override
  State<_MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<_MemoryPage> {
  late Future<WalkMemory?> loaded = widget.store.read(
    widget.memory.id,
    widget.memory.draft,
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<WalkMemory?>(
    future: loaded,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      final m = snapshot.data;
      if (snapshot.hasError || m == null) {
        return Center(
          child: TextButton(
            onPressed: () => setState(
              () => loaded = widget.store.read(
                widget.memory.id,
                widget.memory.draft,
              ),
            ),
            child: const Text('Could not load memory · Retry'),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (m.hasPhoto)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      backgroundColor: Colors.black,
                      appBar: AppBar(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        title: const Text('Photo'),
                      ),
                      body: Center(
                        child: InteractiveViewer(
                          minScale: .8,
                          maxScale: 5,
                          child: MemoryPhoto(memory: m, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                ),
                child: Semantics(
                  button: true,
                  label: 'Open photo full screen',
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: MemoryPhoto(memory: m),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            memoryDate(context, m),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          if (m.note.isNotEmpty)
            SelectableText(
              m.note,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          if (m.hasLocation)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Row(
                children: [
                  Icon(Icons.place_outlined, size: 18),
                  SizedBox(width: 6),
                  Text('A place worth remembering'),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      );
    },
  );
}
