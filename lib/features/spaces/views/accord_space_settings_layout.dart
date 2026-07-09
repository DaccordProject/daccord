part of 'accord_space_settings.dart';

/// Lays out the space-settings sections in one scrolling page. On wide
/// (desktop) viewports the editable [form] and the [actions] tiles sit in two
/// side-by-side columns constrained to a readable max width; on narrow
/// viewports they stack into a single column (the mobile layout).
class _AdaptiveSettingsBody extends StatelessWidget {
  const _AdaptiveSettingsBody({
    required this.form,
    required this.actions,
    this.error,
  });

  final List<Widget> form;
  final List<Widget> actions;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this the two columns would be too cramped, so stack them.
        final twoColumn = constraints.maxWidth >= 880;
        if (!twoColumn) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ...form,
              const Divider(height: 24),
              ...actions,
              if (error != null) error!,
            ],
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: form,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: actions,
                        ),
                      ),
                    ],
                  ),
                  if (error != null) error!,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Section headers use the shared SectionHeader from
// shared/components/section_header.dart.
