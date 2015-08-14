from numpy.testing import assert_warns

import pywt


def test_intwave_deprecation():
    wavelet = pywt.Wavelet('db3')
    assert_warns(DeprecationWarning, pywt.intwave, wavelet)


def test_centrfrq_deprecation():
    wavelet = pywt.Wavelet('db3')
    assert_warns(DeprecationWarning, pywt.centrfrq, wavelet)


def test_scal2frq_deprecation():
    wavelet = pywt.Wavelet('db3')
    assert_warns(DeprecationWarning, pywt.scal2frq, wavelet, 1)


def test_orthfilt_deprecation():
    assert_warns(DeprecationWarning, pywt.orthfilt, range(6))


old_modes = ['zpd',
             'cpd',
             'sym',
             'ppd',
             'sp1',
             'per',
             ]


def test_MODES_from_object_deprecation():
    for mode in old_modes:
        assert_warns(DeprecationWarning, pywt.MODES.from_object, mode)


def test_MODES_attributes_deprecation():
    def get_mode(Modes, name):
        return getattr(Modes, name)

    for mode in old_modes:
        assert_warns(DeprecationWarning, get_mode, pywt.Modes, mode)


def test_MODES_attributes_usage_deprecation():
    for mode in old_modes:
        assert_warns(DeprecationWarning, pywt.dwt, range(10), 'db3', mode)
