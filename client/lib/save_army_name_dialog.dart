import 'package:material_ui/material_ui.dart';

class SaveArmyNameDialog extends StatefulWidget {
  const SaveArmyNameDialog({
    super.key,
    required this.title,
    this.initialName,
  });

  final String title;
  final String? initialName;

  @override
  State<SaveArmyNameDialog> createState() => _SaveArmyNameDialogState();
}

class _SaveArmyNameDialogState extends State<SaveArmyNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'List name'),
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (value) => _save(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _save(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save(BuildContext context, String input) {
    final name = input.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }
}
