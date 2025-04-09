# TODO


## 16/3/2025

- Comment lines of sending audio or media request for testing. (Uncomment when demo)

- The recorded video plays correctly with the built-in player, but when played within the app using plugins, its orientation shifts to horizontal and appears blurry.

    - Possible causes include the plugins wechat_camera_picker, video_player, and their underlying dependency, camera.
    - After reimplementing using only the camera plugin, the issue persists, suggesting a high likelihood that the problem originates from the camera plugin itself.
    - camere: ^0.11.1 solves this.
    - However, the media file stored in Gallery will be .temp extension which affect SOS triggered recording.

- Update chat UI to support audio and media review functionalities.

- Unify API in Flask

- Include query when sending media

## 17/3/2025

- Problem: Whenever user send a media, only the media type but not media content is stored in chat history on cloud. This causes we are just loading the media type without any information about what the actual media content is.
    - Firebase Cloud Storage
    - Whenever send a media, ask Gemini to return both a transcription of the media and its response based on that media (plus the user query). This will also work without Cloud Storage
            - Cost efficiency
            - Chat history integration
            - Bandwidth optimization
            - Persistence of information

## 27/3/2025
- Implemented Daily Crime, Historical Crime Map Pages
- Integrated Twilio API for sending SMS to emergency contacts
- Havent test chat and nearby emergency notification function
- Able to send media in helpers chat room? (Through Cloud Storage)