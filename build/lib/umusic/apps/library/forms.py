from django import forms


class TrackMetadataForm(forms.Form):
    title = forms.CharField(max_length=255)
    artist = forms.CharField(max_length=255, label="Singer / artist")
    album = forms.CharField(max_length=255, required=False)
    year = forms.IntegerField(min_value=1000, max_value=9999, required=False)
    track_number = forms.IntegerField(min_value=1, max_value=65535, required=False)
    disc_number = forms.IntegerField(min_value=1, max_value=65535, required=False)
    genres = forms.CharField(
        max_length=1000, required=False, help_text="Comma-separated genres"
    )
