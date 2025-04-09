import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer';
import '../components/utils.dart';
import 'package:geolocator/geolocator.dart';



class CrimeNewsPage extends StatefulWidget {
  final String currentUserId;
  
  const CrimeNewsPage({Key? key, required this.currentUserId}) : super(key: key);

  @override
  State<CrimeNewsPage> createState() => _CrimeNewsPageState();
}

class _CrimeNewsPageState extends State<CrimeNewsPage> {
  final String _apiKey =
      "pub_756443c104c9bf41de51c0f8efd7222a5d524";
  final String _googleApi = "YOUR_API_KEY";
  List<NewsItem> newsItems = [];
  bool isLoading = true;
  String? errorMessage;
  String _currentUserId = "";
  String _currentLocation = "";
  final List<String> _queries = [
    // "rape",
    "crime"
    // "robbery",
    // "kidnap",
    // "domestic%20violence",
    // "sexual%20assault",
    // "femicide",
    // "harassment",
    // "abuse",
    // "violence%20against%20women"
  ];

  @override
  void initState() {
    super.initState();
    _currentUserId = widget.currentUserId;
    _refresehLocationNews();
  }

  Future<void> _refresehLocationNews() async {
    try {
      Position? position = await getUserLocation(_currentUserId);
      _currentLocation = await _reverseGeocode(position!.latitude, position.longitude);
      setState(() {
        fetchCrimeNews();
      });
    } catch (e) {
      log('Error getting current location: $e');
      setState(() {
        isLoading = false;
      });
      return;
    }
  }

String _extractAddressInfo(List<dynamic> components) {
  for (final comp in components) {
    final types = comp['types'] as List<dynamic>;
    if (types.contains('sublocality')) {
      return comp["long_name"];
    }
    if (types.contains('locality')) {
      return comp["long_name"];
    }
    if (types.contains('administrative_area_level_1')) {
      return comp["long_name"];
    }
    if (types.contains('country')) {
      return comp["long_name"];
    }
  }
  return "";
}

// The reverse geocoding function.
Future<String> _reverseGeocode(double lat, double lon) async {
  try {
    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lon&key=$_googleApi"
    );

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['results'] != null && data['results'].isNotEmpty) {
        // Get the address_components list from the first result.
        final components = data['results'][0]['address_components'] as List<dynamic>;
        // Use our helper function to extract the desired address information.
        return _extractAddressInfo(components);
      }
    }
  } catch (e) {
    debugPrint("Error in reverse geocoding: $e");
  }
  
  return "Unknown Address";
}


  Future<void> fetchCrimeNews() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      for (String q in _queries) {

        var s = 'https://newsdata.io/api/1/latest?apikey=$_apiKey&q=$q&country=my&removeduplicate=1';
        final response = await http.get(
          Uri.parse(s),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'success') {
            setState(() {
              newsItems.addAll(
                (data['results'] as List)
                    .map((item) => NewsItem.fromJson(item))
                    .toList(),
              );
              isLoading = false;
            });
          } else {
            setState(() {
              errorMessage =
                  data['results']['message'] ?? 'Failed to fetch news';
              isLoading = false;
            });
          }
        } else {
          setState(() {
            errorMessage =
                'Failed to fetch news. Status code: ${response.statusCode}';
            isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error fetching news: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Latest Crime News'),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchCrimeNews,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: fetchCrimeNews,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : newsItems.isEmpty
                  ? const Center(child: Text('No crime news found'))
                  : RefreshIndicator(
                      onRefresh: fetchCrimeNews,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: newsItems.length,
                        itemBuilder: (context, index) {
                          final item = newsItems[index];
                          return NewsCard(newsItem: item);
                        },
                      ),
                    ),
    );
  }
}

class NewsCard extends StatelessWidget {
  final NewsItem newsItem;

  const NewsCard({Key? key, required this.newsItem}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _openNewsUrl(newsItem.link),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (newsItem.imageUrl != null)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(
                  newsItem.imageUrl!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 100,
                      width: double.infinity,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image,
                          size: 50, color: Colors.grey),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    newsItem.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (newsItem.description != null) ...[
                    Text(
                      newsItem.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(newsItem.pubDate),
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                      if (newsItem.source != null)
                        Text(
                          newsItem.source!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final DateTime dateTime = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return dateStr;
    }
  }

  void _openNewsUrl(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    }
  }
}

class NewsItem {
  final String title;
  final String? description;
  final String link;
  final String? imageUrl;
  final String pubDate;
  final String? source;

  NewsItem({
    required this.title,
    this.description,
    required this.link,
    this.imageUrl,
    required this.pubDate,
    this.source,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    return NewsItem(
      title: json['title'] ?? 'No Title',
      description: json['description'],
      link: json['link'] ?? '',
      imageUrl: json['image_url'],
      pubDate: json['pubDate'] ?? DateTime.now().toIso8601String(),
      source: json['source_id'],
    );
  }
}
