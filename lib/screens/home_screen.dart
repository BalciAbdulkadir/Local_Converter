import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import '../core/converter_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<XFile> _selectedFiles = [];
  bool _isDragging = false;
  String _targetFormat = 'PNG';
  final List<String> _formats = ['PNG', 'JPG', 'BMP', 'PDF'];

  /// Sistem dosya seçicisinden kullanıcının seçtiği dosyaları ekler.
  /// Adds files selected by the user from the system file picker.
  Future<void> _pickFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );

    if (result != null) {
      setState(() {
        _selectedFiles.addAll(result.xFiles);
      });
    }
  }

  /// Belirtilen indeksteki dosyayı seçili dosyaları listesinden çıkarır.
  /// Removes the file at the specified index from the selected files list.
  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Local Format Converter',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: DropTarget(
                onDragDone: (detail) {
                  setState(() {
                    _selectedFiles.addAll(detail.files);
                  });
                },
                onDragEntered: (detail) {
                  setState(() => _isDragging = true);
                },
                onDragExited: (detail) {
                  setState(() => _isDragging = false);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _isDragging
                        ? Colors.blueGrey.withOpacity(0.3)
                        : Colors.black12,
                    border: Border.all(
                      color: _isDragging
                          ? Colors.blueAccent
                          : Colors.grey.shade700,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 72,
                          color: _isDragging ? Colors.blueAccent : Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Dosyaları Buraya Sürükle',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: _isDragging
                                    ? Colors.blueAccent
                                    : Colors.white70,
                              ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _pickFiles,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Veya Sistemden Seç'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Hedef Format:',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: _targetFormat,
                        underline: Container(
                          height: 2,
                          color: Colors.blueAccent,
                        ),
                        items: _formats.map((String format) {
                          return DropdownMenuItem<String>(
                            value: format,
                            child: Text(
                              format,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() => _targetFormat = newValue);
                          }
                        },
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _selectedFiles.isEmpty
                        ? null
                        : () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Dönüşüm başladı, bekle...'),
                              ),
                            );

                            final converter =
                                ConverterService(); // Dosyanın en üstüne import etmeyi unutma!

                            await converter.convertFiles(
                              _selectedFiles,
                              _targetFormat,
                              (message) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(message),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                            );
                          },
                    icon: const Icon(Icons.transform),
                    label: const Text('Dönüştür'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              flex: 3,
              child: _selectedFiles.isEmpty
                  ? const Center(
                      child: Text(
                        'Henüz dosya seçilmedi.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _selectedFiles.length,
                      itemBuilder: (context, index) {
                        return Card(
                          color: Colors.white10,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: const Icon(
                              Icons.image,
                              color: Colors.blueGrey,
                            ),
                            title: Text(
                              _selectedFiles[index].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _removeFile(index),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
